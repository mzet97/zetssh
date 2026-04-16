import SwiftUI

struct SessionDetailView: View {
    let session: Session?
    var tabId: UUID? = nil
    var onConnectionStateChanged: ((UUID, Bool) -> Void)?

    @State private var connectionStarted = false
    @State private var showingTerminalSettings = false
    @State private var showingSFTP = false
    @State private var activeEngine: (any SSHEngine)?

    var body: some View {
        Group {
            if let session {
                if connectionStarted {
                    SSHTerminalView(
                        host:           session.host,
                        port:           session.port,
                        username:       session.username,
                        sessionId:      session.id,
                        privateKeyPath: session.privateKeyPath,
                        onConnectionEnded: {
                            connectionStarted = false
                            activeEngine = nil
                        },
                        onEngineReady: { engine in
                            activeEngine = engine
                        }
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
        .onChange(of: session?.id) {
            connectionStarted = false
            activeEngine = nil
        }
        .onChange(of: connectionStarted) {
            guard let tabId else { return }
            onConnectionStateChanged?(tabId, connectionStarted)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingTerminalSettings = true
                } label: {
                    Label("Terminal Appearance", systemImage: "paintpalette")
                }
                .help("Configure terminal theme and font")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showingSFTP = true
                } label: {
                    Label("SFTP", systemImage: "folder.badge.gearshape")
                }
                .help("Abrir File Browser SFTP")
                .disabled(!connectionStarted)
            }
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive) {
                    activeEngine?.disconnect()
                    connectionStarted = false
                    activeEngine = nil
                } label: {
                    Label("Desconectar", systemImage: "xmark.circle")
                }
                .help("Encerrar sessão SSH")
                .disabled(!connectionStarted)
            }
        }
        .sheet(isPresented: $showingTerminalSettings) {
            TerminalSettingsView()
        }
        .sheet(isPresented: $showingSFTP) {
            if let engine = activeEngine as? RealSSHEngine {
                FileBrowserView(
                    viewModel: FileBrowserViewModel(),
                    engine: engine
                )
                .frame(minWidth: 560, minHeight: 480)
            } else {
                Text("Conecte-se primeiro para usar o SFTP")
                    .frame(minWidth: 460, minHeight: 400)
            }
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
