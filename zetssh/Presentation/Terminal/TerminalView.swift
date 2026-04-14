import SwiftUI
import SwiftTerm
import NIOCore

// MARK: - SSHTerminalView

/// NSViewRepresentable que integra SwiftTerm (emulação de terminal VT100/xterm)
/// com RealSSHEngine (SwiftNIO-SSH) para uma sessão SSH 100% in-process.
/// Não há subprocess externo — protocolo SSH implementado diretamente.
struct SSHTerminalView: NSViewRepresentable {
    let host: String
    let port: Int
    let username: String
    let sessionId: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SwiftTerm.TerminalView {
        let termView = SwiftTerm.TerminalView(frame: .zero)
        termView.terminalDelegate = context.coordinator
        context.coordinator.terminalView = termView

        let password = (try? KeychainService.shared.fetchPassword(forSessionId: sessionId)) ?? ""
        let engine   = RealSSHEngine()
        engine.delegate = context.coordinator
        context.coordinator.engine   = engine
        context.coordinator.host     = host
        context.coordinator.port     = port
        context.coordinator.username = username
        context.coordinator.password = password

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
        var engine:      (any SSHEngine)?
        var host:        String = ""
        var port:        Int    = 22
        var username:    String = ""
        var password:    String = ""
        var didConnect:  Bool   = false
        weak var terminalView: SwiftTerm.TerminalView?

        func connect() {
            guard let engine, let termView = terminalView else { return }
            termView.feed(text: "Connecting to \(username)@\(host):\(port)...\r\n")
            Task { @MainActor in
                do {
                    try await engine.connect(host: host, port: port, username: username)
                    try await engine.authenticate(password: password)
                } catch {
                    termView.feed(text: "\r\n\u{1B}[31mConnection failed: \(error.localizedDescription)\u{1B}[0m\r\n")
                }
            }
        }
    }
}

// MARK: - SSHClientDelegate

extension SSHTerminalView.Coordinator: SSHClientDelegate {
    /// Dados recebidos do servidor SSH → alimenta o emulador de terminal.
    func onDataReceived(_ data: ByteBuffer) {
        var buf = data
        guard let bytes = buf.readBytes(length: buf.readableBytes), !bytes.isEmpty else { return }
        terminalView?.feed(byteArray: bytes[...])
    }

    func onError(_ error: Error) {
        terminalView?.feed(text: "\r\n\u{1B}[31mSSH Error: \(error.localizedDescription)\u{1B}[0m\r\n")
    }

    func onDisconnected() {
        terminalView?.feed(text: "\r\n\u{1B}[33m[Connection closed. Select a session to reconnect.]\u{1B}[0m\r\n")
    }
}

// MARK: - TerminalViewDelegate

extension SSHTerminalView.Coordinator: TerminalViewDelegate {
    /// Tecla pressionada pelo usuário → envia para o servidor via SSH.
    func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
        engine?.sendData(Array(data))
    }

    /// PTY redimensionado → notifica o servidor para ajustar o tamanho do terminal.
    func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
        engine?.resize(cols: newCols, rows: newRows)
    }

    // --- Callbacks opcionais ---

    func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
    func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
    func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {}
    func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {}
    func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
}
