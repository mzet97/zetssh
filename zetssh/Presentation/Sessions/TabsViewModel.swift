import Foundation
import Combine

@MainActor
final class TabsViewModel: ObservableObject {
    /// The ordered list of currently open tabs.
    @Published private(set) var tabs: [ActiveSession] = []
    /// The `id` of the currently selected tab, or `nil` when no tabs are open.
    @Published var selectedTabId: UUID?

    // MARK: - Public API

    /// Opens a tab for `session`.
    /// - If a tab for this session already exists, selects it without creating a duplicate.
    /// - If the session is new, appends a tab and selects it.
    func open(session: Session) {
        if let existing = tabs.first(where: { $0.session.id == session.id }) {
            selectedTabId = existing.id
            return
        }
        let tab = ActiveSession(session: session)
        tabs.append(tab)
        selectedTabId = tab.id
    }

    /// Closes the tab identified by `tabId`.
    /// If the closed tab was selected, selects the nearest remaining tab,
    /// or sets `selectedTabId` to `nil` when no tabs remain.
    func close(tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs.remove(at: index)
        if selectedTabId == tabId {
            if tabs.isEmpty {
                selectedTabId = nil
            } else {
                let nextIndex = max(0, index - 1)
                selectedTabId = tabs[nextIndex].id
            }
        }
    }

    // MARK: - Convenience

    /// The currently selected `ActiveSession`, if any.
    var selectedTab: ActiveSession? {
        guard let id = selectedTabId else { return nil }
        return tabs.first { $0.id == id }
    }
}
