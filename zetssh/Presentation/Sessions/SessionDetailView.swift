import SwiftUI

struct SessionDetailView: View {
    let session: Session?
    var tabId: UUID? = nil
    var onConnectionStateChanged: ((UUID, Bool) -> Void)?
    var onToggleFavorite: ((Session) -> Void)?
    var onRecordConnectionStarted: ((Session) -> Void)?
    var onRecordConnectionEnded: (() -> Void)?

    @State private var connectionStarted = false
    @State private var showingTerminalSettings = false
    @State private var showingSFTP = false
    @State private var activeEngine: (any SSHEngine)?
    @State private var showTunnelBadge = true
    @State private var showReconnectDialog = false
    @State private var reconnectAttempts = 0
    @State private var showFindBar = false
    @State private var findText = ""

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
                                showReconnectDialog = true
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
        .overlay(alignment: .topTrailing) {
            if showFindBar, connectionStarted {
                findBar
                    .padding(12)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
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
            if connectionStarted, let session {
                onRecordConnectionStarted?(session)
            } else if !connectionStarted {
                onRecordConnectionEnded?()
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    if let session { onToggleFavorite?(session) }
                } label: {
                    Label(
                        (session?.isFavorite ?? false) ? "Unfavorite" : "Favorite",
                        systemImage: (session?.isFavorite ?? false) ? "star.fill" : "star"
                    )
                }
                .help("Toggle favorite")
                .disabled(session == nil)
            }
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(connectionStarted ? Color.green : KineticColors.outline)
                        .frame(width: 8, height: 8)
                        .shadow(
                            color: connectionStarted ? Color.green.opacity(0.5) : .clear,
                            radius: 4
                        )
                    Text(connectionStarted ? "Connected" : "Disconnected")
                        .font(.system(size: 11))
                        .foregroundStyle(connectionStarted ? Color.green : KineticColors.onSurfaceVariant)
                }
            }
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
                Button {
                    showFindBar.toggle()
                    if !showFindBar { findText = "" }
                } label: {
                    Label("Find", systemImage: "magnifyingglass")
                }
                .help("Buscar no terminal (⌘F)")
                .keyboardShortcut("f", modifiers: .command)
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
        .alert("Conexão Encerrada", isPresented: $showReconnectDialog) {
            Button("Reconectar") {
                reconnectAttempts += 1
                connectionStarted = true
            }
            Button("Cancelar", role: .cancel) {
                reconnectAttempts = 0
            }
        } message: {
            if let session {
                Text("A conexão com \(session.name) foi encerrada. Deseja tentar reconectar?")
            } else {
                Text("A conexão foi encerrada. Deseja tentar reconectar?")
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

    private var findBar: some View {
        HStack(spacing: 8) {
            TextField("Buscar no terminal...", text: $findText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .frame(width: 200)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(KineticColors.surfaceContainerHighest)
                )

            Button {
                showFindBar = false
                findText = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(KineticColors.onSurfaceVariant)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(KineticColors.surfaceContainer)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        )
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
