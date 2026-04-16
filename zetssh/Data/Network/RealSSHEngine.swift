import Foundation
import NIOCore
import NIOPosix
@preconcurrency import NIOSSH
import Crypto
import Security

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

    private enum ConnectionState: Equatable {
        case idle, connecting, connected, disconnecting
    }

    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var channel: Channel?
    private var sshChildChannel: Channel?
    private var connectionState: ConnectionState = .idle

    private var pendingHost: String = ""
    private var pendingPort: Int = AppConstants.defaultSSHPort
    private var pendingUsername: String = ""

    public weak var delegate: SSHClientDelegate?

    public var isConnected: Bool { connectionState == .connected }
    public var isConnecting: Bool { connectionState == .connecting }

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
        guard connectionState == .idle else {
            throw SSHConnectionError.alreadyConnecting
        }
        connectionState = .connecting
        let authDelegate = PasswordAuthenticationDelegate(
            username: pendingUsername,
            password: password
        )
        do {
            try await establishConnection(authDelegate: authDelegate)
            connectionState = .connected
            await emitHostKeyWarningIfNeeded()
        } catch {
            connectionState = .idle
            throw error
        }
    }

    public func authenticate(privateKeyPath: URL, passphrase: String?) async throws {
        guard connectionState == .idle else {
            throw SSHConnectionError.alreadyConnecting
        }
        connectionState = .connecting

        // Read PEM file from disk.
        let pemString: String
        do {
            pemString = try String(contentsOf: privateKeyPath, encoding: .utf8)
        } catch {
            connectionState = .idle
            AppLogger.shared.log(
                "Falha ao ler chave privada em \(privateKeyPath.path): \(error)",
                category: .security, level: .error
            )
            throw SSHConnectionError.authenticationFailed
        }

        // Parse the private key using the Security framework (handles OpenSSH, PKCS#8, SEC1, passphrase).
        let privateKey: NIOSSHPrivateKey
        do {
            privateKey = try Self.loadPrivateKey(pemString: pemString, passphrase: passphrase)
        } catch {
            connectionState = .idle
            AppLogger.shared.log(
                "Falha ao parsear chave privada: \(error)",
                category: .security, level: .error
            )
            throw SSHConnectionError.authenticationFailed
        }

        let authDelegate = PrivateKeyAuthenticationDelegate(
            username: pendingUsername,
            privateKey: privateKey
        )

        do {
            try await establishConnection(authDelegate: authDelegate)
            connectionState = .connected
            await emitHostKeyWarningIfNeeded()
        } catch {
            connectionState = .idle
            throw error
        }
    }

    public func disconnect() {
        guard connectionState == .connected || connectionState == .connecting else { return }
        connectionState = .disconnecting
        AppLogger.shared.log("Desconectando SSH...", category: .network, level: .info)
        _ = sshChildChannel?.close()
        _ = channel?.close()
        sshChildChannel = nil
        channel = nil
        group.shutdownGracefully { [weak self] _ in
            DispatchQueue.main.async {
                self?.connectionState = .idle
                AppLogger.shared.log("EventLoopGroup encerrado.", category: .network, level: .info)
            }
        }
    }

    // MARK: - Helpers

    /// Emite aviso de host desconhecido no terminal logo após conexão.
    @MainActor
    private func emitHostKeyWarningIfNeeded() async {
        guard let warning = HostKeyVerificationService.shared.consumeTerminalWarning() else { return }
        guard let child = sshChildChannel else { return }
        var buffer = child.allocator.buffer(capacity: warning.utf8.count)
        buffer.writeString(warning)
        delegate?.onDataReceived(buffer)
    }

    private func establishConnection(authDelegate: NIOSSHClientUserAuthenticationDelegate) async throws {
        let host = pendingHost
        let port = pendingPort
        let serverAuth = HostKeyVerificationDelegate(host: host, port: port)
        // Captura delegate no MainActor antes de entrar em closures NIO (nonisolated)
        let capturedDelegate = delegate

        AppLogger.shared.log("[SSH 1/5] Iniciando TCP para \(host):\(port)...", category: .network, level: .info)

        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelOption(ChannelOptions.socketOption(.so_keepalive), value: 1)
            .connectTimeout(.seconds(15))
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

        let conn: Channel
        do {
            conn = try await bootstrap.connect(host: host, port: port).get()
        } catch {
            AppLogger.shared.log("[SSH 1/5] FALHOU TCP: \(error)", category: .network, level: .error)
            throw error
        }
        self.channel = conn
        AppLogger.shared.log("[SSH 2/5] TCP conectado. Aguardando handshake SSH + autenticação...", category: .network, level: .info)

        let childChannel = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Channel, Error>) in
            let promise = conn.eventLoop.makePromise(of: Channel.self)
            promise.futureResult.whenComplete { result in
                switch result {
                case .success(let ch):
                    AppLogger.shared.log("[SSH 4/5] Canal de sessão aberto.", category: .network, level: .info)
                    continuation.resume(returning: ch)
                case .failure(let err):
                    AppLogger.shared.log("[SSH 4/5] FALHOU canal: \(err)", category: .network, level: .error)
                    continuation.resume(throwing: err)
                }
            }
            conn.pipeline.handler(type: NIOSSHHandler.self).whenComplete { result in
                switch result {
                case .failure(let err):
                    AppLogger.shared.log("[SSH 3/5] FALHOU obter NIOSSHHandler: \(err)", category: .network, level: .error)
                    promise.fail(err)
                case .success(let sshHandler):
                    AppLogger.shared.log("[SSH 3/5] NIOSSHHandler pronto. Abrindo canal de sessão...", category: .network, level: .info)
                    // Apenas adiciona o handler no initializer — NÃO envia eventos aqui.
                    // O canal ainda não está ativo dentro do initializer; enviar eventos
                    // causaria deadlock (future nunca completa).
                    sshHandler.createChannel(promise, channelType: .session) { childChannel, _ in
                        AppLogger.shared.log("[SSH 3.5] Configurando pipeline do canal...", category: .network, level: .info)
                        return childChannel.pipeline.addHandlers([
                            SSHKeepaliveHandler(
                                interval: .seconds(60),
                                maxMissed: 3,
                                delegate: capturedDelegate
                            ),
                            SSHInboundDataHandler(delegate: capturedDelegate)
                        ])
                    }
                }
            }
        }

        // Canal agora ativo — podemos enviar eventos SSH normalmente.
        AppLogger.shared.log("[SSH 4.1] Canal ativo. Enviando PTY request...", category: .network, level: .info)
        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: 80,
            terminalRowHeight: 24,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )
        try await childChannel.triggerUserOutboundEvent(ptyRequest).get()

        AppLogger.shared.log("[SSH 4.2] PTY OK. Enviando Shell request...", category: .network, level: .info)
        try await childChannel.triggerUserOutboundEvent(
            SSHChannelRequestEvent.ShellRequest(wantReply: true)
        ).get()

        self.sshChildChannel = childChannel
        AppLogger.shared.log("[SSH 5/5] Shell SSH aberto com sucesso!", category: .network, level: .info)
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
        // group já é encerrado em disconnect(); o OS recicla os threads se deinit ocorrer antes
    }

    // MARK: - Private Key Loading

    /// Load a PEM private key file into a NIOSSHPrivateKey.
    /// Parses the PEM header to dispatch to the correct Crypto key type.
    /// Supported formats:
    /// - "OPENSSH PRIVATE KEY" — Ed25519 or EC (OpenSSH binary format)
    /// - "PRIVATE KEY" — PKCS#8 Ed25519 or EC
    /// - "EC PRIVATE KEY" — SEC1 EC
    private static func loadPrivateKey(pemString: String, passphrase: String?) throws -> NIOSSHPrivateKey {
        // Detect PEM type from the header line.
        let trimmed = pemString.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.components(separatedBy: "\n").first ?? ""

        if firstLine.contains("OPENSSH PRIVATE KEY") {
            return try loadOpenSSHPrivateKey(pemString: pemString, passphrase: passphrase)
        } else if firstLine.contains("EC PRIVATE KEY") {
            return try loadSEC1ECKey(pemString: pemString)
        } else if firstLine.contains("PRIVATE KEY") {
            // PKCS#8 — could be EC or Ed25519
            return try loadPKCS8Key(pemString: pemString)
        } else {
            throw SSHConnectionError.authenticationFailed
        }
    }

    /// Parse an OpenSSH-format private key ("OPENSSH PRIVATE KEY").
    /// Handles unencrypted Ed25519 and EC keys; passphrase-encrypted keys are
    /// loaded via SecItemImport (macOS Security framework).
    private static func loadOpenSSHPrivateKey(pemString: String, passphrase: String?) throws -> NIOSSHPrivateKey {
        // For passphrase-protected keys, delegate to SecItemImport.
        if let pp = passphrase, !pp.isEmpty {
            return try loadViaSecImport(pemString: pemString, passphrase: pp)
        }

        // Decode the base64 body.
        let lines = pemString.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        let b64 = lines.joined()
        guard let data = Data(base64Encoded: b64) else {
            throw SSHConnectionError.authenticationFailed
        }

        // OpenSSH private key binary layout:
        // "openssh-key-v1\0"  (magic, 15 bytes + NUL = 16 bytes)
        // string: ciphername
        // string: kdfname
        // string: kdfoptions
        // uint32: number of keys
        // string: public key blob
        // string: private key blob
        //
        // Inside the private key blob (unencrypted):
        // uint32: check1
        // uint32: check2  (must equal check1)
        // <key type string + key bytes>
        var offset = 0

        func readBytes(_ n: Int) throws -> Data {
            guard offset + n <= data.count else { throw SSHConnectionError.authenticationFailed }
            defer { offset += n }
            return data[offset ..< offset + n]
        }

        func readUInt32() throws -> UInt32 {
            let b = try readBytes(4)
            return b.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        }

        func readString() throws -> Data {
            let len = Int(try readUInt32())
            return try readBytes(len)
        }

        // Magic header: "openssh-key-v1\0"
        let magic = try readBytes(15)
        guard magic == Data("openssh-key-v1".utf8) else { throw SSHConnectionError.authenticationFailed }
        _ = try readBytes(1)  // NUL terminator

        let cipherName = try readString()
        let kdfName = try readString()
        _ = try readString()  // kdfoptions

        guard String(data: cipherName, encoding: .utf8) == "none",
              String(data: kdfName, encoding: .utf8) == "none" else {
            // Encrypted — fall back to SecItemImport without passphrase hope.
            throw SSHConnectionError.authenticationFailed
        }

        let numKeys = try readUInt32()
        guard numKeys == 1 else { throw SSHConnectionError.authenticationFailed }

        _ = try readString()  // public key blob

        let privateBlob = try readString()
        var blobOffset = 0

        func blobReadBytes(_ n: Int) throws -> Data {
            guard blobOffset + n <= privateBlob.count else { throw SSHConnectionError.authenticationFailed }
            defer { blobOffset += n }
            return privateBlob[blobOffset ..< blobOffset + n]
        }

        func blobReadUInt32() throws -> UInt32 {
            let b = try blobReadBytes(4)
            return b.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        }

        func blobReadString() throws -> Data {
            let len = Int(try blobReadUInt32())
            return try blobReadBytes(len)
        }

        let check1 = try blobReadUInt32()
        let check2 = try blobReadUInt32()
        guard check1 == check2 else { throw SSHConnectionError.authenticationFailed }

        let keyTypeData = try blobReadString()
        guard let keyType = String(data: keyTypeData, encoding: .utf8) else {
            throw SSHConnectionError.authenticationFailed
        }

        switch keyType {
        case "ssh-ed25519":
            _ = try blobReadString()  // public key (32 bytes)
            let privateAndPublic = try blobReadString()  // 64 bytes: private (32) + public (32)
            let rawPrivate = privateAndPublic.prefix(32)
            let ed25519 = try Curve25519.Signing.PrivateKey(rawRepresentation: rawPrivate)
            return NIOSSHPrivateKey(ed25519Key: ed25519)

        case "ecdsa-sha2-nistp256":
            _ = try blobReadString()  // curve name
            _ = try blobReadString()  // public key point
            let rawPrivate = try blobReadString()
            let p256 = try P256.Signing.PrivateKey(rawRepresentation: rawPrivate)
            return NIOSSHPrivateKey(p256Key: p256)

        case "ecdsa-sha2-nistp384":
            _ = try blobReadString()
            _ = try blobReadString()
            let rawPrivate = try blobReadString()
            let p384 = try P384.Signing.PrivateKey(rawRepresentation: rawPrivate)
            return NIOSSHPrivateKey(p384Key: p384)

        case "ecdsa-sha2-nistp521":
            _ = try blobReadString()
            _ = try blobReadString()
            let rawPrivate = try blobReadString()
            let p521 = try P521.Signing.PrivateKey(rawRepresentation: rawPrivate)
            return NIOSSHPrivateKey(p521Key: p521)

        default:
            throw SSHConnectionError.authenticationFailed
        }
    }

    /// Parse a SEC1 EC private key ("EC PRIVATE KEY" PEM header).
    private static func loadSEC1ECKey(pemString: String) throws -> NIOSSHPrivateKey {
        let lines = pemString.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        guard let derData = Data(base64Encoded: lines.joined()) else {
            throw SSHConnectionError.authenticationFailed
        }
        // SEC1 DER for P-256 is ~121 bytes, P-384 ~185 bytes, P-521 ~223 bytes.
        // Try each curve; the correct one will succeed.
        if let key = try? P256.Signing.PrivateKey(derRepresentation: derData) {
            return NIOSSHPrivateKey(p256Key: key)
        } else if let key = try? P384.Signing.PrivateKey(derRepresentation: derData) {
            return NIOSSHPrivateKey(p384Key: key)
        } else if let key = try? P521.Signing.PrivateKey(derRepresentation: derData) {
            return NIOSSHPrivateKey(p521Key: key)
        } else {
            throw SSHConnectionError.authenticationFailed
        }
    }

    /// Parse a PKCS#8 private key ("PRIVATE KEY" PEM header).
    private static func loadPKCS8Key(pemString: String) throws -> NIOSSHPrivateKey {
        let lines = pemString.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        guard let derData = Data(base64Encoded: lines.joined()) else {
            throw SSHConnectionError.authenticationFailed
        }
        // Try EC curves; PKCS#8 wraps the SEC1 key.
        if let key = try? P256.Signing.PrivateKey(derRepresentation: derData) {
            return NIOSSHPrivateKey(p256Key: key)
        } else if let key = try? P384.Signing.PrivateKey(derRepresentation: derData) {
            return NIOSSHPrivateKey(p384Key: key)
        } else if let key = try? P521.Signing.PrivateKey(derRepresentation: derData) {
            return NIOSSHPrivateKey(p521Key: key)
        }
        // Try Ed25519 via PKCS#8 DER: OID 1.3.101.112 + 34-byte octet string wrapping 32-byte seed.
        // PKCS#8 structure: SEQUENCE { SEQUENCE { OID }, OCTET STRING { OCTET STRING { seed } } }
        // The raw seed starts at byte 16 in canonical encoding.
        if derData.count >= 48 {
            let seed = derData[16..<48]
            if let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) {
                return NIOSSHPrivateKey(ed25519Key: key)
            }
        }
        throw SSHConnectionError.authenticationFailed
    }

    /// Fallback: use macOS SecItemImport to load a passphrase-protected OpenSSH key,
    /// then extract the key material via SecKeyCopyExternalRepresentation.
    private static func loadViaSecImport(pemString: String, passphrase: String) throws -> NIOSSHPrivateKey {
        guard let pemData = pemString.data(using: .utf8) else {
            throw SSHConnectionError.authenticationFailed
        }

        // Use SecKeychainItemImport (deprecated but still functional on macOS for PEM keys).
        var importedItems: CFArray?
        var inputFormat = SecExternalFormat.formatPEMSequence
        var itemType = SecExternalItemType.itemTypePrivateKey

        let ppData = passphrase.data(using: .utf8)! as CFData
        var keyParams = SecItemImportExportKeyParameters()
        keyParams.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
        keyParams.passphrase = Unmanaged.passRetained(ppData as AnyObject)

        let status = SecItemImport(
            pemData as CFData,
            nil,
            &inputFormat,
            &itemType,
            [],
            &keyParams,
            nil,
            &importedItems
        )

        keyParams.passphrase?.release()

        guard status == errSecSuccess,
              let items = importedItems as? [AnyObject],
              !items.isEmpty else {
            throw SSHConnectionError.authenticationFailed
        }

        var secKey: SecKey?
        for item in items where CFGetTypeID(item as CFTypeRef) == SecKeyGetTypeID() {
            secKey = (item as! SecKey)
            break
        }

        guard let key = secKey else { throw SSHConnectionError.authenticationFailed }

        var cfError: Unmanaged<CFError>?
        guard let keyDataCF = SecKeyCopyExternalRepresentation(key, &cfError) else {
            cfError?.release()
            throw SSHConnectionError.authenticationFailed
        }
        let keyData = keyDataCF as Data

        // Determine key type.
        guard let attrs = SecKeyCopyAttributes(key) as? [String: Any],
              let keyType = attrs[kSecAttrKeyType as String] as? String else {
            throw SSHConnectionError.authenticationFailed
        }

        if keyType == (kSecAttrKeyTypeECSECPrimeRandom as String) {
            // External representation for EC private keys is x9.63 = 04 || x || y || k (private scalar at end)
            // Use kSecAttrKeySizeInBits from attrs to select the correct curve instead of inferring from blob size.
            let keySizeBits = attrs[kSecAttrKeySizeInBits as String] as? Int ?? 0
            switch keySizeBits {
            case 256:
                let p256 = try P256.Signing.PrivateKey(rawRepresentation: keyData.suffix(32))
                return NIOSSHPrivateKey(p256Key: p256)
            case 384:
                let p384 = try P384.Signing.PrivateKey(rawRepresentation: keyData.suffix(48))
                return NIOSSHPrivateKey(p384Key: p384)
            case 521:
                let p521 = try P521.Signing.PrivateKey(rawRepresentation: keyData.suffix(66))
                return NIOSSHPrivateKey(p521Key: p521)
            default:
                throw SSHConnectionError.authenticationFailed
            }
        } else {
            // Assume Ed25519: external representation is the 32-byte seed.
            let ed25519 = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData.prefix(32))
            return NIOSSHPrivateKey(ed25519Key: ed25519)
        }
    }

    /// Retorna o canal SSH principal para abertura de subsistemas (ex: SFTP).
    /// Requer conexão ativa (authenticate() chamado com sucesso).
    public func openSFTPChannel() async throws -> Channel {
        guard let conn = channel, connectionState == .connected else {
            throw SSHConnectionError.unknown
        }
        return conn
    }

    func openSFTPClient() async throws -> SFTPClient {
        guard let conn = channel, connectionState == .connected else {
            throw SSHConnectionError.unknown
        }

        let sftpChannel = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Channel, Error>) in
            let promise = conn.eventLoop.makePromise(of: Channel.self)
            promise.futureResult.whenComplete { result in
                switch result {
                case .success(let ch): continuation.resume(returning: ch)
                case .failure(let err): continuation.resume(throwing: err)
                }
            }
            conn.pipeline.handler(type: NIOSSHHandler.self).whenSuccess { handler in
                handler.createChannel(promise, channelType: .session) { ch, _ in
                    ch.pipeline.addHandler(SFTPChannelHandler())
                }
            }
        }

        try await sftpChannel.triggerUserOutboundEvent(
            SSHChannelRequestEvent.SubsystemRequest(subsystem: "sftp", wantReply: true)
        ).get()

        var initBuf = sftpChannel.allocator.buffer(capacity: 9)
        initBuf.writeInteger(UInt32(5))
        initBuf.writeInteger(UInt8(1))
        initBuf.writeInteger(UInt32(0))
        initBuf.writeInteger(UInt32(3))
        let initData = SSHChannelData(type: .channel, data: .byteBuffer(initBuf))
        try await sftpChannel.writeAndFlush(initData).get()

        return SFTPClient(channel: sftpChannel)
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

private final class PrivateKeyAuthenticationDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let privateKey: NIOSSHPrivateKey

    init(username: String, privateKey: NIOSSHPrivateKey) {
        self.username = username
        self.privateKey = privateKey
    }

    nonisolated func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        if availableMethods.contains(.publicKey) {
            nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(
                username: username,
                serviceName: "",
                offer: .privateKey(.init(privateKey: privateKey))
            ))
        } else {
            // Server does not advertise publicKey — signal end of attempts.
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

// MARK: - SSHKeepaliveHandler

/// Detecta conexões SSH mortas por inatividade.
/// Se nenhum dado for recebido em `interval * maxMissed` segundos, encerra o canal
/// e notifica o delegate com `connectionTimedOut`.
private final class SSHKeepaliveHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = SSHChannelData

    private let interval: TimeAmount
    private let maxMissed: Int
    private weak var delegate: (any SSHClientDelegate)?

    private var missedIntervals = 0
    private var keepaliveTask: RepeatedTask?

    init(interval: TimeAmount, maxMissed: Int, delegate: (any SSHClientDelegate)?) {
        self.interval = interval
        self.maxMissed = maxMissed
        self.delegate = delegate
    }

    func channelActive(context: ChannelHandlerContext) {
        let channel = context.channel
        keepaliveTask = context.eventLoop.scheduleRepeatedTask(
            initialDelay: interval,
            delay: interval,
            notifying: nil
        ) { [weak self] task in
            guard let self else { task.cancel(); return }
            self.missedIntervals += 1
            if self.missedIntervals >= self.maxMissed {
                task.cancel()
                AppLogger.shared.log(
                    "[SSH Keepalive] Sem resposta após \(self.maxMissed) intervalos. Encerrando.",
                    category: .network, level: .warning
                )
                let d = self.delegate
                DispatchQueue.main.async { d?.onError(SSHConnectionError.connectionTimedOut) }
                channel.close(promise: nil)
            }
        }
        context.fireChannelActive()
    }

    func channelInactive(context: ChannelHandlerContext) {
        keepaliveTask?.cancel()
        keepaliveTask = nil
        context.fireChannelInactive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        missedIntervals = 0
        context.fireChannelRead(data)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        keepaliveTask?.cancel()
        keepaliveTask = nil
        context.fireErrorCaught(error)
    }
}

// MARK: - SSHInboundDataHandler

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
