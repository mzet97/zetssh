import SwiftUI

struct HostsListView: View {
    @ObservedObject var viewModel: SessionViewModel
    var searchText: String = ""
    var onConnect: (Session) -> Void
    var onEdit: (Session) -> Void

    @State private var selectedSession: Session?
    @State private var showingDeleteConfirmation = false
    @State private var sessionToDelete: Session?

    private var filteredSessions: [Session] {
        guard !searchText.isEmpty else { return viewModel.sessions }
        return viewModel.sessions.filter { session in
            session.name.localizedCaseInsensitiveContains(searchText) ||
            session.host.localizedCaseInsensitiveContains(searchText) ||
            session.username.localizedCaseInsensitiveContains(searchText)
        }
    }

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
        .alert("Delete Session", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                sessionToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    viewModel.delete(session)
                    if selectedSession?.id == session.id {
                        selectedSession = nil
                    }
                    sessionToDelete = nil
                }
            }
        } message: {
            if let session = sessionToDelete {
                Text("Are you sure you want to delete \"\(session.name)\"? This cannot be undone.")
            } else {
                Text("Are you sure you want to delete this session?")
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                header

                if viewModel.sessions.isEmpty {
                    emptyState
                } else if filteredSessions.isEmpty {
                    noResultsState
                } else {
                    hostsGrid
                }
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connections")
                    .font(KineticFont.caption.font)
                    .foregroundStyle(KineticColors.onSurfaceVariant)
                Text("Hosts")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(KineticColors.onSurface)
            }

            Spacer()

            Text("\(viewModel.sessions.count) SAVED")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(KineticColors.onSurfaceVariant)
        }
    }

    // MARK: - Hosts Grid

    private var hostsGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .foregroundStyle(KineticColors.primary)
                Text("All Hosts")
                    .font(KineticFont.headline.font)
                    .foregroundStyle(KineticColors.onSurface)
                KineticColors.outlineVariant.opacity(0.3)
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                Text("\(filteredSessions.count) HOSTS")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(KineticColors.onSurfaceVariant)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(filteredSessions) { session in
                    hostCard(session)
                }
            }
        }
    }

    // MARK: - Host Card

    @ViewBuilder
    private func hostCard(_ session: Session) -> some View {
        let isSelected = selectedSession?.id == session.id

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: session.privateKeyPath != nil ? "key.fill" : "lock.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(session.privateKeyPath != nil ? KineticColors.tertiary : KineticColors.primary)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill((session.privateKeyPath != nil ? KineticColors.tertiary : KineticColors.primary).opacity(0.1))
                    )

                Spacer()

                if session.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(KineticColors.primary)
                }
            }

            Text(session.name)
                .font(KineticFont.body.font)
                .fontWeight(.semibold)
                .foregroundStyle(KineticColors.onSurface)
                .lineLimit(1)
                .padding(.top, 12)

            Text(session.host)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(KineticColors.onSurfaceVariant)
                .padding(.top, 2)

            HStack {
                Text(session.privateKeyPath != nil ? "Key Auth" : "Password")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(KineticColors.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(KineticColors.tertiaryContainer.opacity(0.3))
                    )

                Text(":\(session.port)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(KineticColors.onSurfaceVariant)

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
        .contextMenu {
            Button {
                onConnect(session)
            } label: {
                Label("Connect", systemImage: "terminal")
            }

            Button {
                onEdit(session)
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Divider()

            Button {
                viewModel.toggleFavorite(session)
            } label: {
                Label(
                    session.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: session.isFavorite ? "star.slash" : "star"
                )
            }

            Divider()

            Button(role: .destructive) {
                sessionToDelete = session
                showingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Detail Sidebar

    @ViewBuilder
    private var detailSidebar: some View {
        if let session = selectedSession {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("Session Details")
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
                        detailRow(label: "Host", value: session.host)
                        detailRow(label: "Port", value: "\(session.port)")
                        detailRow(label: "User", value: session.username)
                        detailRow(label: "Auth", value: session.privateKeyPath != nil ? "Private Key" : "Password")
                        if let keyPath = session.privateKeyPath {
                            detailRow(label: "Key", value: URL(fileURLWithPath: keyPath).lastPathComponent)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Actions")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.2)
                            .foregroundStyle(KineticColors.onSurfaceVariant)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            quickActionButton(icon: "terminal", label: "Connect") { onConnect(session) }
                            quickActionButton(icon: "pencil", label: "Edit") { onEdit(session) }
                            quickActionButton(icon: session.isFavorite ? "star.slash" : "star", label: session.isFavorite ? "Unfav" : "Favorite") {
                                viewModel.toggleFavorite(session)
                            }
                            quickActionButton(icon: "trash", label: "Delete", isDestructive: true) {
                                sessionToDelete = session
                                showingDeleteConfirmation = true
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(KineticColors.surfaceContainerLow)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(KineticColors.onSurfaceVariant)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(KineticColors.onSurface)
            Spacer()
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

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)
            Image(systemName: "server.rack")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(KineticColors.outline)
            Text("No saved hosts yet")
                .font(KineticFont.body.font)
                .foregroundStyle(KineticColors.onSurfaceVariant)
            Text("Create a new session to get started")
                .font(KineticFont.caption.font)
                .foregroundStyle(KineticColors.outline)
        }
        .frame(maxWidth: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(KineticColors.outline)
            Text("No hosts match your search")
                .font(KineticFont.body.font)
                .foregroundStyle(KineticColors.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
    }
}
