import SwiftUI
import AppKit

struct SessionConnectionView: View {
    let session: Session
    let onConnect: () -> Void

    @State private var showCopied = false

    private var sshCommand: String {
        var cmd = "ssh"
        if let keyPath = session.privateKeyPath {
            cmd += " -i \(keyPath)"
        }
        cmd += " \(session.username)@\(session.host)"
        if session.port != 22 {
            cmd += " -p \(session.port)"
        }
        return cmd
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "server.rack")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(session.name)
                    .font(.title2.bold())
                Text("\(session.username)@\(session.host):\(session.port)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button(action: onConnect) {
                Label("Conectar", systemImage: "terminal")
                    .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(sshCommand, forType: .string)
                showCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showCopied = false
                }
            } label: {
                Label(
                    showCopied ? "Copiado!" : "Copiar Comando SSH",
                    systemImage: showCopied ? "checkmark" : "doc.on.doc"
                )
                .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
