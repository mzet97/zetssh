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
        terminalView?.feed(
            text: "\r\n\u{1B}[31mSSH Error: \(error.localizedDescription)\u{1B}[0m\r\n"
        )
    }

    func onDisconnected() {
        terminalView?.feed(
            text: "\r\n\u{1B}[33m[Connection closed. Select a session to reconnect.]\u{1B}[0m\r\n"
        )
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
