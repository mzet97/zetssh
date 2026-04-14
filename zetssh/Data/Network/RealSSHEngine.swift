import Foundation
import NIOCore
import NIOPosix
@preconcurrency import NIOSSH

// MARK: - Delegate

public protocol SSHClientDelegate: AnyObject, Sendable {
    func onDataReceived(_ data: ByteBuffer)
    func onError(_ error: Error)
    func onDisconnected()
}

// MARK: - RealSSHEngine

/// Motor SSH real usando SwiftNIO-SSH.
/// Segue o protocolo SSHEngine: connect() armazena os parâmetros;
/// authenticate() estabelece a conexão com as credenciais fornecidas.
public final class RealSSHEngine: SSHEngine {

    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var channel: Channel?
    private var sshChildChannel: Channel?

    private var pendingHost: String = ""
    private var pendingPort: Int = AppConstants.defaultSSHPort
    private var pendingUsername: String = ""

    public weak var delegate: SSHClientDelegate?

    public init() {}

    // MARK: SSHEngine

    public func connect(host: String, port: Int, username: String) async throws {
        pendingHost = host
        pendingPort = port
        pendingUsername = username
        AppLogger.shared.log(
            "Parâmetros armazenados: \(username)@\(host):\(port)",
            category: .network, level: .info
        )
    }

    public func authenticate(password: String) async throws {
        let authDelegate = PasswordAuthenticationDelegate(
            username: pendingUsername,
            password: password
        )
        try await establishConnection(authDelegate: authDelegate)
    }

    public func authenticate(privateKeyPath: URL, passphrase: String?) async throws {
        // Post-MVP: autenticação por chave privada
        AppLogger.shared.log(
            "Autenticação por chave ainda não implementada no RealSSHEngine.",
            category: .security, level: .warning
        )
        throw SSHConnectionError.unknown
    }

    public func disconnect() {
        AppLogger.shared.log("Desconectando SSH Nativo...", category: .network, level: .info)
        _ = channel?.close()
        channel = nil
        sshChildChannel = nil
    }

    // MARK: - Helpers

    private func establishConnection(authDelegate: NIOSSHClientUserAuthenticationDelegate) async throws {
        let host = pendingHost
        let port = pendingPort
        let serverAuth = HostKeyVerificationDelegate(host: host, port: port)
        // Captura delegate no MainActor antes de entrar em closures NIO (nonisolated)
        let capturedDelegate = delegate

        AppLogger.shared.log("Conectando a \(host):\(port)...", category: .network, level: .info)

        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .connectTimeout(.seconds(10))
            .channelInitializer { channel in
                channel.pipeline.addHandlers([
                    NIOSSHHandler(
                        role: .client(.init(
                            userAuthDelegate: authDelegate,
                            serverAuthDelegate: serverAuth
                        )),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    )
                ])
            }

        let conn = try await bootstrap.connect(host: host, port: port).get()
        self.channel = conn

        let childChannel = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Channel, Error>) in
            let promise = conn.eventLoop.makePromise(of: Channel.self)
            promise.futureResult.whenComplete { result in
                switch result {
                case .success(let ch): continuation.resume(returning: ch)
                case .failure(let err): continuation.resume(throwing: err)
                }
            }
            conn.pipeline.handler(type: NIOSSHHandler.self).whenSuccess { sshHandler in
                sshHandler.createChannel(promise, channelType: .session) { childChannel, _ in
                    childChannel.pipeline.addHandler(
                        SSHInboundDataHandler(delegate: capturedDelegate)
                    ).flatMap {
                        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
                            wantReply: true,
                            term: "xterm-256color",
                            terminalCharacterWidth: 80,
                            terminalRowHeight: 24,
                            terminalPixelWidth: 800,
                            terminalPixelHeight: 600,
                            terminalModes: SSHTerminalModes([:])
                        )
                        return childChannel.triggerUserOutboundEvent(ptyRequest).flatMap {
                            childChannel.triggerUserOutboundEvent(
                                SSHChannelRequestEvent.ShellRequest(wantReply: true)
                            )
                        }
                    }
                }
            }
        }

        self.sshChildChannel = childChannel
        AppLogger.shared.log("Shell SSH aberto com sucesso.", category: .network, level: .info)
    }

    /// Envia um evento de resize de PTY para o servidor.
    public func resize(cols: Int, rows: Int) {
        guard let child = sshChildChannel else { return }
        let event = SSHChannelRequestEvent.WindowChangeRequest(
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0
        )
        child.triggerUserOutboundEvent(event, promise: nil)
    }

    public func sendData(_ data: [UInt8]) {
        guard let child = sshChildChannel else { return }
        var buffer = child.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        let ioData = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
        child.writeAndFlush(ioData, promise: nil)
    }

    deinit {
        try? group.syncShutdownGracefully()
    }
}

// MARK: - Private Delegates

private final class PasswordAuthenticationDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let password: String

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    nonisolated func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        if availableMethods.contains(.password) {
            nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(
                username: username,
                serviceName: "",
                offer: .password(.init(password: password))
            ))
        } else {
            nextChallengePromise.succeed(nil)
        }
    }
}

private final class HostKeyVerificationDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let host: String
    private let port: Int

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    nonisolated func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        let host = self.host
        let port = self.port
        Task { @MainActor in
            let result = await HostKeyVerificationService.shared.verify(
                host: host, port: port, key: hostKey
            )
            switch result {
            case .trusted, .userAccepted:
                validationCompletePromise.succeed(())
            case .userRejected:
                validationCompletePromise.fail(SSHConnectionError.hostRejected)
            case .mismatch:
                validationCompletePromise.fail(SSHConnectionError.hostKeyMismatch)
            }
        }
    }
}

private final class SSHInboundDataHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData

    // delegate é @MainActor; usamos weak ref e despachamos para a main queue
    private weak var delegate: (any SSHClientDelegate)?

    init(delegate: (any SSHClientDelegate)?) {
        self.delegate = delegate
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = channelData.data else { return }
        let d = delegate
        DispatchQueue.main.async { d?.onDataReceived(buffer) }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        let d = delegate
        DispatchQueue.main.async { d?.onError(error) }
    }

    func channelInactive(context: ChannelHandlerContext) {
        let d = delegate
        DispatchQueue.main.async { d?.onDisconnected() }
    }
}
