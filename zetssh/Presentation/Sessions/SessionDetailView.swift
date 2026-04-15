import SwiftUI

struct SessionDetailView: View {
    let session: Session?

    @State private var connectionStarted = false

    var body: some View {
        Group {
            if let session {
                if connectionStarted {
                    SSHTerminalView(
                        host:           session.host,
                        port:           session.port,
                        username:       session.username,
                        sessionId:      session.id,
                        privateKeyPath: session.privateKeyPath
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                } else {
                    SessionConnectionView(session: session) {
                        connectionStarted = true
                    }
                }
            } else {
                emptyState
            }
        }
        .navigationTitle(session?.name ?? "ZetSSH")
        .onChange(of: session?.id) { _ in
            connectionStarted = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("Selecione uma sessão para conectar")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
