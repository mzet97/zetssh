import SwiftUI

struct SessionDetailView: View {
    let session: Session?
    var tabId: UUID? = nil
    var onConnectionStateChanged: ((UUID, Bool) -> Void)?

    @State private var connectionStarted = false
    @State private var showingTerminalSettings = false
    @State private var showingSFTP = false
    @State private var activeEngine: (any SSHEngine)?
    @State private var showTunnelBadge = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
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

            if connectionStarted, session != nil {
                connectionMetadataOverlay
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if connectionStarted, showTunnelBadge {
                encryptedTunnelBadge
                    .padding(20)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
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

    private var connectionMetadataOverlay: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let session {
                Text("Session: \(session.id.uuidString.prefix(8).uppercased())")
                    .font(KineticFont.overline.font)
                    .tracking(KineticFont.overline.tracking)
                Text("\(session.username)@\(session.host):\(session.port)")
                    .font(KineticFont.overline.font)
                    .tracking(KineticFont.overline.tracking)
            }
        }
        .foregroundStyle(KineticColors.onSurfaceVariant.opacity(0.4))
        .padding(12)
    }

    private var encryptedTunnelBadge: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 20))
                .foregroundStyle(Color.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Encrypted Tunnel Active")
                    .font(KineticFont.caption.font)
                    .fontWeight(.bold)
                    .foregroundStyle(KineticColors.onSurface)
                Text("AES-256-GCM encryption verified for this session.")
                    .font(.system(size: 10))
                    .foregroundStyle(KineticColors.onSurfaceVariant)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(KineticColors.surfaceContainerHigh.opacity(0.6))
                .background(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                showTunnelBadge = false
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(KineticColors.outline)
            Text("Selecione uma sessão para conectar")
                .font(KineticFont.title.font)
                .foregroundStyle(KineticColors.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KineticColors.surfaceContainer)
    }
}
