import SwiftUI

struct SessionConnectionView: View {
    let session: Session
    let onConnect: () -> Void

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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
