import SwiftUI

struct MultiSessionView: View {
    @ObservedObject var tabsVM: TabsViewModel
    var onToggleFavorite: ((Session) -> Void)?
    var onRecordConnectionStarted: ((Session) -> Void)?
    var onRecordConnectionEnded: (() -> Void)?
    var onAddSession: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if !tabsVM.tabs.isEmpty {
                TabBarView(tabsVM: tabsVM, onAddTab: { onAddSession?() })
            }

            ZStack {
                if tabsVM.tabs.isEmpty {
                    emptyState
                } else {
                    // Keep all SessionDetailView instances alive simultaneously
                    // so each tab's @State (connectionStarted) is preserved.
                    ForEach(tabsVM.tabs) { tab in
                        SessionDetailView(
                            session: tab.session,
                            tabId: tab.id,
                            onConnectionStateChanged: { tabId, connected in
                                tabsVM.updateConnectionState(
                                    connected ? .connected : .disconnected,
                                    forTabId: tabId
                                )
                            },
                            onToggleFavorite: { session in
                                onToggleFavorite?(session)
                            },
                            onRecordConnectionStarted: { session in
                                onRecordConnectionStarted?(session)
                            },
                            onRecordConnectionEnded: {
                                onRecordConnectionEnded?()
                            }
                        )
                            .opacity(tabsVM.selectedTabId == tab.id ? 1 : 0)
                            .allowsHitTesting(tabsVM.selectedTabId == tab.id)
                            .zIndex(tabsVM.selectedTabId == tab.id ? 1 : 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("Selecione uma sessão na barra lateral para conectar")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
