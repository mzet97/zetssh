import SwiftUI
import AppKit

struct FavoritesView: View {
    @ObservedObject var viewModel: SessionViewModel
    var onConnect: (Session) -> Void

    @State private var selectedSession: Session?
    @State private var showingSFTP = false
    @State private var showingRebootConfirmation = false
    @State private var rebootTargetSession: Session?

    var body: some View {
        HStack(spacing: 0) {
            mainContent

            if selectedSession != nil {
                GhostDivider(vertical: true)
                detailSidebar
                    .frame(width: 300)
            }
        }
        .background(KineticColors.surface)
        .sheet(isPresented: $showingSFTP) {
            if let session = selectedSession {
                sftpSheet(for: session)
            }
        }
        .alert("Confirm Reboot", isPresented: $showingRebootConfirmation) {
            Button("Cancel", role: .cancel) {
                rebootTargetSession = nil
            }
            Button("Reboot", role: .destructive) {
                if let session = rebootTargetSession {
                    rebootServer(session)
                }
                rebootTargetSession = nil
            }
        } message: {
            if let session = rebootTargetSession {
                Text("Are you sure you want to reboot \(session.name)? This will disconnect all active sessions.")
            } else {
                Text("Are you sure you want to reboot this server?")
            }
        }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                header

                if viewModel.sessions.isEmpty {
                    emptyState
                } else {
                    let favorites = viewModel.sessions.filter(\.isFavorite)
                    if favorites.isEmpty {
                        emptyState
                    } else {
                        folderSection(
                            title: "Favorites",
                            icon: "star.fill",
                            iconColor: KineticColors.primary,
                            sessions: favorites
                        )
                    }
                }
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Curation")
                    .font(KineticFont.caption.font)
                    .foregroundStyle(KineticColors.onSurfaceVariant)
                Text("Favorites")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(KineticColors.onSurface)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func folderSection(title: String, icon: String, iconColor: Color, sessions: [Session]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(KineticFont.headline.font)
                    .foregroundStyle(KineticColors.onSurface)
                KineticColors.outlineVariant.opacity(0.3)
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                Text("\(sessions.count) NODES")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(KineticColors.onSurfaceVariant)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(sessions) { session in
                    serverCard(session)
                }
            }
        }
    }

    @ViewBuilder
    private func serverCard(_ session: Session) -> some View {
        let isSelected = selectedSession?.id == session.id

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "terminal")
                    .font(.system(size: 18))
                    .foregroundStyle(KineticColors.primary)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(KineticColors.primary.opacity(0.1))
                    )

                Spacer()

                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(KineticColors.primary)
            }

            Text(session.name)
                .font(KineticFont.body.font)
                .fontWeight(.semibold)
                .foregroundStyle(KineticColors.onSurface)
                .padding(.top, 12)

            Text(session.host)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(KineticColors.onSurfaceVariant)
                .padding(.top, 2)

            HStack {
                Text("Active")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(KineticColors.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(KineticColors.secondaryContainer.opacity(0.3))
                    )

                Spacer()
            }
            .padding(.top, 12)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? KineticColors.surfaceContainer : KineticColors.surfaceContainerLow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedSession = session
            }
        }
        .onDoubleTapGesture {
            onConnect(session)
        }
    }

    @ViewBuilder
    private var detailSidebar: some View {
        if let session = selectedSession {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("Selection Info")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.2)
                            .foregroundStyle(KineticColors.onSurfaceVariant)
                        Spacer()
                        Button {
                            selectedSession = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10))
                                .foregroundStyle(KineticColors.outline)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.name)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(KineticColors.onSurface)
                        Text("ssh \(session.username)@\(session.host)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(KineticColors.primary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Actions")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.2)
                            .foregroundStyle(KineticColors.onSurfaceVariant)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                             quickActionButton(icon: "terminal", label: "Shell") { onConnect(session) }
                             quickActionButton(icon: "folder.zip", label: "SFTP") { showingSFTP = true }
                             quickActionButton(icon: "doc.on.doc", label: "Copy SSH") { copySSHCommand(session) }
                             quickActionButton(icon: "power", label: "Reboot", isDestructive: true) {
                                 rebootTargetSession = session
                                 showingRebootConfirmation = true
                             }
                        }
                    }
                }
                .padding(20)
            }
            .background(KineticColors.surfaceContainerLow)
        }
    }

    private func quickActionButton(icon: String, label: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundStyle(isDestructive ? KineticColors.error : KineticColors.onSurfaceVariant)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(KineticColors.surfaceContainerHighest.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
    }

    private func copySSHCommand(_ session: Session) {
        var cmd = "ssh"
        if let keyPath = session.privateKeyPath {
            cmd += " -i \(keyPath)"
        }
        cmd += " \(session.username)@\(session.host)"
        if session.port != 22 {
            cmd += " -p \(session.port)"
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(cmd, forType: .string)
    }

    @ViewBuilder
    private func sftpSheet(for session: Session) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("SFTP — \(session.name)")
                    .font(KineticFont.headline.font)
                    .foregroundStyle(KineticColors.onSurface)
                Spacer()
                Button("Close") { showingSFTP = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(KineticColors.surfaceContainerLow)

            Text("Connect to this server first to use SFTP.\nOpen a terminal session, then use the SFTP toolbar button.")
                .font(KineticFont.body.font)
                .foregroundStyle(KineticColors.onSurfaceVariant)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 460, minHeight: 400)
        .background(KineticColors.surface)
    }

    private func rebootServer(_ session: Session) {
        let cmd = "sudo shutdown -r now"
        let fullCommand = "ssh \(session.username)@\(session.host) -p \(session.port) \(cmd)"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fullCommand, forType: .string)

        let alert = NSAlert()
        alert.messageText = "Reboot Command Copied"
        alert.informativeText = "The reboot command has been copied to your clipboard.\n\nPaste it in a terminal to execute:\n\(fullCommand)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "star")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(KineticColors.outline)
            Text("No favorite servers yet")
                .font(KineticFont.body.font)
                .foregroundStyle(KineticColors.onSurfaceVariant)
            Text("Mark sessions as favorites to see them here")
                .font(KineticFont.caption.font)
                .foregroundStyle(KineticColors.outline)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

extension View {
    func onDoubleTapGesture(action: @escaping () -> Void) -> some View {
        self.simultaneousGesture(
            TapGesture(count: 2).onEnded { action() }
        )
    }
}
