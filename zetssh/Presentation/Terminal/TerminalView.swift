import SwiftUI
import SwiftTerm
import NIOCore
import GRDB

// MARK: - SSHTerminalView

/// NSViewRepresentable integrating SwiftTerm (VT100/xterm emulation)
/// with RealSSHEngine (SwiftNIO-SSH) for a 100% in-process SSH session.
struct SSHTerminalView: NSViewRepresentable {
    let host:           String
    let port:           Int
    let username:       String
    let sessionId:      UUID
    /// Absolute path to the private key file, or `nil` when using password auth.
    let privateKeyPath: String?
    /// Fired when the connection ends (disconnect, timeout, or error) after a brief delay.
    var onConnectionEnded: (() -> Void)?
    /// Fired once after successful authentication with the active engine reference.
    var onEngineReady:    ((any SSHEngine) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SwiftTerm.TerminalView {
        let termView = SwiftTerm.TerminalView(frame: .zero)

        // Apply persisted terminal theme
        if let profile = try? AppDatabase.shared.dbWriter.read({ db in
            try TerminalProfile
                .filter(Column("isDefault") == true)
                .fetchOne(db)
                ?? TerminalProfile.fetchOne(db)
        }) {
            ThemeRegistry.apply(profile: profile, to: termView)
        }

        termView.terminalDelegate = context.coordinator
        context.coordinator.terminalView = termView

        let engine = RealSSHEngine()
        engine.delegate = context.coordinator
        context.coordinator.engine         = engine
        context.coordinator.host           = host
        context.coordinator.port           = port
        context.coordinator.username       = username
        context.coordinator.privateKeyPath = privateKeyPath
        context.coordinator.onConnectionEnded = onConnectionEnded
        context.coordinator.onEngineReady    = onEngineReady

        if let keyPath = privateKeyPath {
            // Private key auth: load passphrase from Keychain (may be nil).
            context.coordinator.passphrase =
                try? KeychainService.shared.fetchPassphrase(forSessionId: sessionId)
            AppLogger.shared.log(
                "Auth mode: private key at \(keyPath)",
                category: .security, level: .info
            )
        } else {
            // Password auth.
            context.coordinator.password =
                (try? KeychainService.shared.fetchPassword(forSessionId: sessionId)) ?? ""
        }

        return termView
    }

    func updateNSView(_ nsView: SwiftTerm.TerminalView, context: Context) {
        guard !context.coordinator.didConnect else { return }
        context.coordinator.didConnect = true
        context.coordinator.connect()
    }

    static func dismantleNSView(_ nsView: SwiftTerm.TerminalView, coordinator: Coordinator) {
        coordinator.engine?.disconnect()
        coordinator.engine = nil
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var engine:         (any SSHEngine)?
        var host:           String  = ""
        var port:           Int     = 22
        var username:       String  = ""
        var password:       String  = ""
        var privateKeyPath: String? = nil
        var passphrase:     String? = nil
        var didConnect:     Bool    = false
        weak var terminalView: SwiftTerm.TerminalView?
        var onConnectionEnded: (() -> Void)?
        var onEngineReady:    ((any SSHEngine) -> Void)?

        func connect() {
            guard let engine, let termView = terminalView else { return }
            termView.feed(text: "Connecting to \(username)@\(host):\(port)...\r\n")

            Task { @MainActor in
                do {
                    try await engine.connect(host: host, port: port, username: username)

                    if let keyPathString = privateKeyPath {
                        let keyURL = URL(fileURLWithPath: keyPathString)
                        termView.feed(text: "Using private key: \(keyPathString)\r\n")
                        try await engine.authenticate(privateKeyPath: keyURL, passphrase: passphrase)
                    } else {
                        try await engine.authenticate(password: password)
                    }
                    self.onEngineReady?(engine)
                } catch {
                    termView.feed(
                        text: "\r\n\u{1B}[31mConnection failed: \(error.localizedDescription)\u{1B}[0m\r\n"
                    )
                }
            }
        }
    }
}

// MARK: - SSHClientDelegate

extension SSHTerminalView.Coordinator: SSHClientDelegate {
    func onDataReceived(_ data: ByteBuffer) {
        var buf = data
        guard let bytes = buf.readBytes(length: buf.readableBytes), !bytes.isEmpty else { return }
        terminalView?.feed(byteArray: bytes[...])
    }

    func onError(_ error: Error) {
        let text: String
        if case SSHConnectionError.connectionTimedOut = error {
            let minutes = Int(AppConstants.Keepalive.intervalSeconds) * AppConstants.Keepalive.maxMissed / 60
            text = "\r\n\u{1B}[33m[Conexão encerrada: servidor não respondeu por \(minutes) minutos.]\u{1B}[0m\r\n" +
                   "\u{1B}[33m[Selecione a sessão na barra lateral para reconectar.]\u{1B}[0m\r\n"
        } else {
            text = "\r\n\u{1B}[31mErro SSH: \(error.localizedDescription)\u{1B}[0m\r\n"
        }
        terminalView?.feed(text: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.onConnectionEnded?()
        }
    }

    func onDisconnected() {
        terminalView?.feed(
            text: "\r\n\u{1B}[33m[Conexão encerrada. Selecione a sessão para reconectar.]\u{1B}[0m\r\n"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.onConnectionEnded?()
        }
    }
}

// MARK: - TerminalViewDelegate

extension SSHTerminalView.Coordinator: TerminalViewDelegate {
    func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
        engine?.sendData(Array(data))
    }

    func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
        engine?.resize(cols: newCols, rows: newRows)
    }

    func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
    func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
    func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {}
    func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {}
    func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
}
