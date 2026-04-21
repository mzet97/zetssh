import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: SessionViewModel
    @ObservedObject var tabsVM: TabsViewModel

    var searchText: String = ""
    var onSectionChanged: ((NavSection) -> Void)?

    @State private var selectedSection: NavSection = .hosts
    @State private var highlightedSessionId: UUID?
    @State private var showingAddSession = false
    @State private var showingImportSSHConfig = false
    @StateObject private var sshConfigImportVM = SSHConfigImportViewModel()
    @State private var showingDeleteConfirmation = false
    @State private var sessionToDelete: Session?

    private var filteredTabs: [ActiveSession] {
        guard !searchText.isEmpty else { return tabsVM.tabs }
        return tabsVM.tabs.filter { tab in
            tab.label.localizedCaseInsensitiveContains(searchText) ||
            tab.session.host.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ZetSSH")
                    .font(KineticFont.headline.font)
                    .foregroundStyle(KineticColors.onSurface)
                Text("SECURE SHELL CLIENT")
                    .font(KineticFont.overline.font)
                    .tracking(KineticFont.overline.tracking)
                    .foregroundStyle(KineticColors.onSurfaceVariant.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 20)

            // MARK: - Navigation Sections
            VStack(spacing: 2) {
                ForEach(NavSection.allCases, id: \.self) { section in
                    navRow(for: section)
                }
            }
            .padding(.horizontal, 8)

            // MARK: - Active Connections
            if !tabsVM.tabs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ACTIVE CONNECTIONS")
                        .font(KineticFont.overline.font)
                        .tracking(KineticFont.overline.tracking)
                        .foregroundStyle(KineticColors.outline)
                        .padding(.horizontal, 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)
                .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(filteredTabs) { tab in
                            activeConnectionRow(for: tab)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }

            Spacer()

            // MARK: - Bottom Actions
            GhostDivider()
                .padding(.bottom, 8)

            HStack(spacing: 4) {
                Button {
                    showingAddSession = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(KineticColors.onSurfaceVariant)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New Session")

                Button {
                    showingImportSSHConfig = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(KineticColors.onSurfaceVariant)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Import SSH Config…")

                Spacer()

                Button {
                    guard let id = highlightedSessionId,
                          let session = viewModel.sessions.first(where: { $0.id == id })
                    else { return }
                    sessionToDelete = session
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(KineticColors.onSurfaceVariant)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(highlightedSessionId == nil)
                .opacity(highlightedSessionId == nil ? 0.4 : 1.0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 240)
        .background(
            KineticColors.surfaceDim
                .opacity(0.7)
                .background(.ultraThinMaterial)
        )
        .sheet(isPresented: $showingAddSession) {
            SessionFormView { newSession, credentials in
                viewModel.save(newSession, credentials: credentials)
                tabsVM.open(session: newSession)
                onSectionChanged?(.hosts)
            }
        }
        .sheet(isPresented: $showingImportSSHConfig) {
            SSHConfigImportView(
                importVM: sshConfigImportVM,
                sessionVM: viewModel,
                isPresented: $showingImportSSHConfig
            )
        }
        .alert("Delete Session", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                sessionToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    deleteSession(session)
                    sessionToDelete = nil
                }
            }
        } message: {
            if let session = sessionToDelete {
                Text("Delete \"\(session.name)\"? This cannot be undone.")
            } else {
                Text("Delete this session?")
            }
        }
    }

    // MARK: - Nav Row

    @ViewBuilder
    private func navRow(for section: NavSection) -> some View {
        let isActive = selectedSection == section

        HStack(spacing: 10) {
            Image(systemName: section.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isActive ? KineticColors.primary : KineticColors.onSurfaceVariant)

            Text(section.rawValue)
                .font(KineticFont.body.font)
                .foregroundStyle(isActive ? KineticColors.primary : KineticColors.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? KineticColors.surfaceContainer.opacity(0.5) : .clear)
        )
        .overlay(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(KineticColors.primary)
                    .frame(width: 3, height: 18)
                    .offset(x: 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedSection = section
            }
            onSectionChanged?(section)
        }
    }

    // MARK: - Active Connection Row

    @ViewBuilder
    private func activeConnectionRow(for tab: ActiveSession) -> some View {
        let isConnected = tab.connectionState == .connected

        HStack(spacing: 8) {
            Circle()
                .fill(isConnected ? Color.green : KineticColors.outline)
                .frame(width: 8, height: 8)
                .shadow(
                    color: isConnected ? Color.green.opacity(0.5) : .clear,
                    radius: 4
                )

            Text(tab.label)
                .font(KineticFont.caption.font)
                .foregroundStyle(isConnected ? KineticColors.onSurface : KineticColors.onSurfaceVariant)
                .lineLimit(1)

            Spacer()

            if tabsVM.selectedTabId == tab.id {
                Circle()
                    .fill(KineticColors.primary)
                    .frame(width: 4, height: 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(tabsVM.selectedTabId == tab.id ? KineticColors.surfaceContainer.opacity(0.3) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            tabsVM.selectedTabId = tab.id
        }
        .contextMenu {
            Button("Disconnect") {
                tabsVM.close(tabId: tab.id)
            }
        }
    }

    // MARK: - Helpers

    private func deleteSession(_ session: Session) {
        if let tab = tabsVM.tabs.first(where: { $0.session.id == session.id }) {
            tabsVM.close(tabId: tab.id)
        }
        viewModel.delete(session)
        if highlightedSessionId == session.id { highlightedSessionId = nil }
    }
}

// MARK: - NavSection

enum NavSection: String, CaseIterable {
    case hosts = "Hosts"
    case favorites = "Favorites"
    case history = "History"

    var icon: String {
        switch self {
        case .hosts: return "server.rack"
        case .favorites: return "star"
        case .history: return "clock.arrow.circlepath"
        }
    }
}
