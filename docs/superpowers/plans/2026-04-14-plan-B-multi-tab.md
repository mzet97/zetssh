# Multi-Tab SSH Sessions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add native macOS multi-tab support so users can open multiple simultaneous SSH sessions inside a single window, each tab fully independent.

**Architecture:** A new `ActiveSession` domain model represents an open tab; `TabsViewModel` owns the tab list and drives selection logic; `TabBarView` renders the horizontal tab strip; `MultiSessionView` composes the bar with per-tab `SessionDetailView` instances; `ContentView` is updated to wire the sidebar into `TabsViewModel.open(session:)` instead of a simple `selectedSessionId` binding. `SessionDetailView` is left untouched — its `connectionStarted` `@State` already resets on session identity change.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (NSViewRepresentable via existing TerminalView), GRDB 6.x, SwiftNIO-SSH, SwiftTerm, macOS 14+

---

## Task 1 — Create `ActiveSession` domain model

**File to create:** `zetssh/zetssh/Domain/Models/ActiveSession.swift`

No persistence needed — `ActiveSession` is a pure in-memory value type representing a tab that is currently open.

- [ ] **Step 1: Create `ActiveSession.swift`**

```swift
// zetssh/zetssh/Domain/Models/ActiveSession.swift
import Foundation

/// Represents a single open SSH tab in the multi-tab interface.
/// This is an in-memory model only — it is never persisted to GRDB.
struct ActiveSession: Identifiable, Equatable {
    /// Unique ID for this open tab instance. Distinct from `session.id`
    /// so the same Session can theoretically be opened twice (future work).
    let id: UUID
    /// The persisted session this tab was opened from.
    let session: Session
    /// Display label shown in the tab bar. Defaults to `session.name`.
    var label: String

    init(session: Session) {
        self.id = UUID()
        self.session = session
        self.label = session.name
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` (no errors).

- [ ] **Step 3: Commit**

```bash
git add zetssh/Domain/Models/ActiveSession.swift
git commit -m "feat: add ActiveSession domain model for multi-tab support"
```

---

## Task 2 — Create `TabsViewModel`

**File to create:** `zetssh/zetssh/Presentation/Sessions/TabsViewModel.swift`

`TabsViewModel` is the single source of truth for the list of open tabs and which tab is selected. It enforces the "no duplicate tabs for the same session" rule.

- [ ] **Step 1: Create `TabsViewModel.swift`**

```swift
// zetssh/zetssh/Presentation/Sessions/TabsViewModel.swift
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
                // Prefer the tab to the left; fall back to the new tab at the same index.
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
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add zetssh/Presentation/Sessions/TabsViewModel.swift
git commit -m "feat: add TabsViewModel with open/close tab logic and duplicate-prevention"
```

---

## Task 3 — Create `TabBarView`

**File to create:** `zetssh/zetssh/Presentation/Sessions/TabBarView.swift`

A horizontal scrollable strip of tabs. Each tab shows the session label and an "×" close button. A "+" button at the right end is reserved for future "new blank tab" functionality; for now it is hidden (no design spec for it yet — sidebar remains the primary entry point).

- [ ] **Step 1: Create `TabBarView.swift`**

```swift
// zetssh/zetssh/Presentation/Sessions/TabBarView.swift
import SwiftUI

struct TabBarView: View {
    @ObservedObject var tabsVM: TabsViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabsVM.tabs) { tab in
                    tabButton(for: tab)
                    Divider().frame(height: 20)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 34)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Private

    @ViewBuilder
    private func tabButton(for tab: ActiveSession) -> some View {
        let isSelected = tabsVM.selectedTabId == tab.id

        HStack(spacing: 4) {
            Text(tab.label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 140, alignment: .leading)

            Button {
                tabsVM.close(tabId: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Fechar aba")
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            isSelected
                ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15)
                : Color.clear
        )
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .frame(height: 2)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            tabsVM.selectedTabId = tab.id
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add zetssh/Presentation/Sessions/TabBarView.swift
git commit -m "feat: add TabBarView with per-tab close button and active-tab underline indicator"
```

---

## Task 4 — Create `MultiSessionView`

**File to create:** `zetssh/zetssh/Presentation/Sessions/MultiSessionView.swift`

`MultiSessionView` stacks `TabBarView` above the content area. The content area uses a `ZStack` of `SessionDetailView` instances — one per tab — with only the selected one visible. Using a `ZStack` (rather than recreating views on selection change) preserves each tab's `connectionStarted` state across tab switches.

- [ ] **Step 1: Create `MultiSessionView.swift`**

```swift
// zetssh/zetssh/Presentation/Sessions/MultiSessionView.swift
import SwiftUI

struct MultiSessionView: View {
    @ObservedObject var tabsVM: TabsViewModel

    var body: some View {
        VStack(spacing: 0) {
            if !tabsVM.tabs.isEmpty {
                TabBarView(tabsVM: tabsVM)
            }

            ZStack {
                if tabsVM.tabs.isEmpty {
                    emptyState
                } else {
                    // Keep all SessionDetailView instances alive simultaneously
                    // so each tab's @State (connectionStarted) is preserved.
                    ForEach(tabsVM.tabs) { tab in
                        SessionDetailView(session: tab.session)
                            .opacity(tabsVM.selectedTabId == tab.id ? 1 : 0)
                            // Prevent hidden tabs from intercepting events.
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
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add zetssh/Presentation/Sessions/MultiSessionView.swift
git commit -m "feat: add MultiSessionView composing TabBarView and per-tab SessionDetailView"
```

---

## Task 5 — Update `ContentView` to wire everything together

**File to modify:** `zetssh/zetssh/Presentation/ContentView.swift`

Replace the `selectedSessionId: UUID?` detail logic with `TabsViewModel`. The sidebar now calls `tabsVM.open(session:)` on row tap instead of binding a selection UUID directly to the detail. The detail column always renders `MultiSessionView`.

- [ ] **Step 1: Update `ContentView.swift`**

Replace the entire file content with:

```swift
// zetssh/zetssh/Presentation/ContentView.swift
import SwiftUI

struct ContentView: View {
    @StateObject private var sessionVM = SessionViewModel()
    @StateObject private var tabsVM   = TabsViewModel()

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: sessionVM, tabsVM: tabsVM)
        } detail: {
            MultiSessionView(tabsVM: tabsVM)
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
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: compiler errors about `SidebarView` not accepting `tabsVM` — that is resolved in the next task.

- [ ] **Step 3: Commit (after Task 6 compiles)**

Defer commit until after Task 6.

---

## Task 6 — Update `SidebarView` to open tabs instead of selecting a session ID

**File to modify:** `zetssh/zetssh/Presentation/Sessions/SidebarView.swift`

`SidebarView` previously drove `selectedSessionId: Binding<UUID?>`. It now receives `tabsVM: TabsViewModel` and calls `tabsVM.open(session:)` when the user taps a session row. The `List` selection binding switches to a local `@State` so the sidebar can highlight the row without coupling to the tab system.

- [ ] **Step 1: Update `SidebarView.swift`**

Replace the entire file content with:

```swift
// zetssh/zetssh/Presentation/Sessions/SidebarView.swift
import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: SessionViewModel
    @ObservedObject var tabsVM: TabsViewModel

    /// Local highlight state — purely visual, does not drive detail content.
    @State private var highlightedSessionId: UUID?
    @State private var showingAddSession = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $highlightedSessionId) {
                Section("Sessions") {
                    ForEach(viewModel.sessions) { session in
                        NavigationLink(value: session.id) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.name).font(.headline)
                                Text("\(session.username)@\(session.host):\(session.port)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button("Deletar", role: .destructive) {
                                deleteSession(session)
                            }
                        }
                    }
                    .onDelete(perform: deleteSessions)
                }
            }
            .onChange(of: highlightedSessionId) { newId in
                guard let id = newId,
                      let session = viewModel.sessions.first(where: { $0.id == id })
                else { return }
                tabsVM.open(session: session)
            }
            .onDeleteCommand {
                guard let id = highlightedSessionId,
                      let session = viewModel.sessions.first(where: { $0.id == id })
                else { return }
                deleteSession(session)
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                Button { showingAddSession = true } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain).padding(8)

                Spacer()

                Button {
                    guard let id = highlightedSessionId,
                          let session = viewModel.sessions.first(where: { $0.id == id })
                    else { return }
                    deleteSession(session)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.plain).padding(8)
                .disabled(highlightedSessionId == nil)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .navigationTitle("ZetSSH")
        .sheet(isPresented: $showingAddSession) {
            SessionFormView { newSession, password in
                viewModel.save(newSession, password: password)
            }
        }
    }

    // MARK: - Helpers

    private func deleteSession(_ session: Session) {
        // Close any open tab for this session before deleting it.
        if let tab = tabsVM.tabs.first(where: { $0.session.id == session.id }) {
            tabsVM.close(tabId: tab.id)
        }
        viewModel.delete(session)
        if highlightedSessionId == session.id { highlightedSessionId = nil }
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            deleteSession(viewModel.sessions[index])
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit `ContentView` + `SidebarView` together**

```bash
git add zetssh/Presentation/ContentView.swift zetssh/Presentation/Sessions/SidebarView.swift
git commit -m "feat: wire TabsViewModel into ContentView and SidebarView for multi-tab navigation"
```

---

## Task 7 — Smoke-test checklist (manual, no unit test framework yet)

Run the app (`⌘R` in Xcode or via `xcodebuild`) and verify each behaviour:

- [ ] **Empty state** — launching the app with no sessions shows the empty-state message in the detail area and no tab bar.
- [ ] **Open first tab** — clicking a session in the sidebar opens a tab, the tab bar appears, the session name is shown in the tab label, and `SessionConnectionView` is visible.
- [ ] **No duplicate tab** — clicking the same session again selects the existing tab without adding a second one.
- [ ] **Open second tab** — clicking a different session adds a second tab; both tabs are independently usable.
- [ ] **Tab switching preserves state** — connect a session in Tab 1 so the terminal is visible; switch to Tab 2; switch back to Tab 1 — the terminal is still running (not reset).
- [ ] **Close tab** — clicking "×" on a tab removes it; the nearest remaining tab is selected automatically.
- [ ] **Close last tab** — removing the only open tab hides the tab bar and shows the empty state again.
- [ ] **Delete session from sidebar closes tab** — right-click → Deletar on a session whose tab is open: the tab closes and the session is removed from GRDB.
- [ ] **Commit after all checks pass**

```bash
git add .
git commit -m "test: manual smoke-test multi-tab flow — all cases pass"
```

---

## Build command reference

```bash
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Run from `/Users/zeitune/src/zetssh/`.

---

## File index

| Action   | Path |
|----------|------|
| Create   | `zetssh/zetssh/Domain/Models/ActiveSession.swift` |
| Create   | `zetssh/zetssh/Presentation/Sessions/TabsViewModel.swift` |
| Create   | `zetssh/zetssh/Presentation/Sessions/TabBarView.swift` |
| Create   | `zetssh/zetssh/Presentation/Sessions/MultiSessionView.swift` |
| Modify   | `zetssh/zetssh/Presentation/ContentView.swift` |
| Modify   | `zetssh/zetssh/Presentation/Sessions/SidebarView.swift` |
| No touch | `zetssh/zetssh/Presentation/Sessions/SessionDetailView.swift` |
| No touch | `zetssh/zetssh/Presentation/Sessions/SessionConnectionView.swift` |
| No touch | `zetssh/zetssh/Presentation/Terminal/TerminalView.swift` |
| No touch | `zetssh/zetssh/Presentation/Sessions/SessionViewModel.swift` |
