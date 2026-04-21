import SwiftUI

struct ContentView: View {
    @StateObject private var sessionVM = SessionViewModel()
    @StateObject private var tabsVM = TabsViewModel()

    @State private var activeTab: TopNavTab = .terminals
    @State private var selectedSection: NavSection = .hosts
    @State private var showingAddSession = false
    @State private var searchText = ""
    @State private var isSplitView = false
    @State private var sessionToEdit: Session?
    @State private var showingEditSession = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                viewModel: sessionVM,
                tabsVM: tabsVM,
                searchText: searchText,
                onSectionChanged: { section in
                    selectedSection = section
                    if activeTab != .terminals {
                        activeTab = .terminals
                    }
                }
            )

            GhostDivider(vertical: true)

            VStack(spacing: 0) {
                TopNavBar(
                    activeTab: $activeTab,
                    searchText: $searchText,
                    onConnect: { showingAddSession = true },
                    onAdd: { showingAddSession = true },
                    onToggleSplit: { isSplitView.toggle() }
                )

                mainContent
            }
            .background(KineticColors.surface)
        }
        .background(KineticColors.surface)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingAddSession) {
            SessionFormView { newSession, credentials in
                sessionVM.save(newSession, credentials: credentials)
                tabsVM.open(session: newSession)
                selectedSection = .hosts
            }
        }
        .sheet(isPresented: $showingEditSession) {
            if let session = sessionToEdit {
                SessionFormView(existingSession: session) { updatedSession, credentials in
                    sessionVM.update(updatedSession, credentials: credentials)
                    sessionToEdit = nil
                }
            }
        }
        .alert("Erro", isPresented: Binding(
            get: { sessionVM.errorMessage != nil },
            set: { if !$0 { sessionVM.errorMessage = nil } }
        )) {
            Button("OK") { sessionVM.errorMessage = nil }
        } message: {
            Text(sessionVM.errorMessage ?? "")
        }
    }

    // MARK: - Main Content Router

    @ViewBuilder
    private var mainContent: some View {
        switch activeTab {
        case .terminals:
            switch selectedSection {
            case .hosts:
                if tabsVM.tabs.isEmpty {
                    HostsListView(
                        viewModel: sessionVM,
                        searchText: searchText,
                        onConnect: { session in
                            tabsVM.open(session: session)
                        },
                        onEdit: { session in
                            sessionToEdit = session
                            showingEditSession = true
                        }
                    )
                } else {
                    MultiSessionView(tabsVM: tabsVM, onToggleFavorite: { session in
                        sessionVM.toggleFavorite(session)
                    }, onRecordConnectionStarted: { session in
                        sessionVM.recordConnectionStarted(session: session)
                    }, onRecordConnectionEnded: {
                        sessionVM.recordConnectionEnded()
                    }, onAddSession: {
                        showingAddSession = true
                    })
                }
            case .favorites:
                FavoritesView(viewModel: sessionVM) { session in
                    tabsVM.open(session: session)
                    selectedSection = .hosts
                }
            case .history:
                HistoryView(viewModel: sessionVM) { session in
                    tabsVM.open(session: session)
                    selectedSection = .hosts
                }
            }
        case .keys:
            KeyManagementView(viewModel: sessionVM)
        case .settings:
            SettingsView()
        }
    }

    private func placeholderView(_ title: String, subtitle: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(KineticColors.outline)
            Text(title)
                .font(KineticFont.headline.font)
                .foregroundStyle(KineticColors.onSurface)
            Text(subtitle)
                .font(KineticFont.caption.font)
                .foregroundStyle(KineticColors.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KineticColors.surfaceContainer)
    }
}
