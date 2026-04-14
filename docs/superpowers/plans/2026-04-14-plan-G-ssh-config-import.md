# SSH Config Import — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Parse `~/.ssh/config` and let the user bulk-import hosts as ZetSSH sessions from a dedicated sheet accessible in the sidebar.

**Architecture:** A pure-Swift line-by-line parser lives in `Data/SSH/`; a thin `SSHConfigEntry` value type in `Domain/Models/` bridges parser output to `Session`; a `@MainActor ObservableObject` view-model in `Presentation/Import/` drives an AppKit `NSOpenPanel` (sandbox-safe) and holds selection state; a SwiftUI sheet in `Presentation/Import/` renders the picker + checklist + import action; the existing `SidebarView` grows an "Importar SSH Config…" menu item wired to the sheet.

**Tech Stack:** SwiftUI, GRDB 6.29.3, AppKit (NSOpenPanel)

**Source root:** `zetssh/zetssh/` (relative to `/Users/zeitune/src/zetssh/`)

---

## Task 1 — Domain model `SSHConfigEntry`

**Files:**
- Create: `zetssh/zetssh/Domain/Models/SSHConfigEntry.swift`

- [ ] **Step 1: Create the value type**

```swift
// zetssh/zetssh/Domain/Models/SSHConfigEntry.swift
import Foundation

/// Represents one parsed `Host` block from an SSH config file.
/// Wildcards (`Host *`) are excluded by the parser before this type is produced.
struct SSHConfigEntry: Identifiable, Hashable {
    /// The alias declared on the `Host` line (e.g. "myserver").
    var alias: String
    /// Resolved hostname — `HostName` value, or falls back to `alias` when absent.
    var hostname: String
    /// SSH username — `User` value, or `NSUserName()` when absent.
    var user: String
    /// TCP port — `Port` value, or 22 when absent.
    var port: Int
    /// Absolute path to the identity file after `~` expansion, or `nil` when absent.
    var identityFile: String?

    /// Stable identity for SwiftUI list diffing.
    var id: String { alias }
}
```

- [ ] **Step 2: Build check**

```bash
xcodebuild -project /Users/zeitune/src/zetssh/zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
cd /Users/zeitune/src/zetssh
git add zetssh/zetssh/Domain/Models/SSHConfigEntry.swift
git commit -m "feat(G): add SSHConfigEntry domain model"
```

---

## Task 2 — Parser `SSHConfigParser`

**Files:**
- Create: `zetssh/zetssh/Data/SSH/SSHConfigParser.swift`

- [ ] **Step 1: Create the parser**

```swift
// zetssh/zetssh/Data/SSH/SSHConfigParser.swift
import Foundation

enum SSHConfigParser {
    /// Parses the text content of an SSH config file and returns one
    /// `SSHConfigEntry` per non-wildcard `Host` block.
    ///
    /// - Parameter content: Raw UTF-8 string of the config file.
    /// - Returns: Ordered array of parsed entries; wildcard hosts are omitted.
    static func parse(content: String) -> [SSHConfigEntry] {
        var entries: [SSHConfigEntry] = []
        var current: SSHConfigEntry?

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip blank lines and comments.
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let parts = trimmed.components(separatedBy: .whitespaces)
            guard parts.count >= 2 else { continue }

            let key   = parts[0].lowercased()
            let value = parts[1...].joined(separator: " ")

            switch key {
            case "host":
                // Flush the previous block (skip wildcards).
                if let c = current, c.alias != "*" {
                    entries.append(c)
                }
                // Start a new block; alias doubles as hostname until HostName overrides it.
                current = SSHConfigEntry(
                    alias: value,
                    hostname: value,
                    user: NSUserName(),
                    port: 22,
                    identityFile: nil
                )

            case "hostname":
                current?.hostname = value

            case "user":
                current?.user = value

            case "port":
                current?.port = Int(value) ?? 22

            case "identityfile":
                // Expand leading `~` to the actual home directory.
                let expanded = value.replacingOccurrences(of: "~", with: NSHomeDirectory())
                current?.identityFile = expanded

            default:
                break
            }
        }

        // Flush the final block.
        if let c = current, c.alias != "*" {
            entries.append(c)
        }

        return entries
    }

    /// Convenience overload: reads a file URL and delegates to `parse(content:)`.
    ///
    /// - Parameter url: File URL of the SSH config file.
    /// - Returns: Parsed entries, or an empty array when the file cannot be read.
    static func parse(url: URL) -> [SSHConfigEntry] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return parse(content: content)
    }
}
```

- [ ] **Step 2: Build check**

```bash
xcodebuild -project /Users/zeitune/src/zetssh/zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
cd /Users/zeitune/src/zetssh
git add zetssh/zetssh/Data/SSH/SSHConfigParser.swift
git commit -m "feat(G): add SSHConfigParser line-by-line parser"
```

---

## Task 3 — View-model `SSHConfigImportViewModel`

**Files:**
- Create: `zetssh/zetssh/Presentation/Import/SSHConfigImportViewModel.swift`

This view-model owns the NSOpenPanel interaction (required for sandbox) and all import state.

- [ ] **Step 1: Create the view-model**

```swift
// zetssh/zetssh/Presentation/Import/SSHConfigImportViewModel.swift
import AppKit
import Combine
import Foundation

@MainActor
final class SSHConfigImportViewModel: ObservableObject {
    // MARK: - Published state

    /// All entries parsed from the selected file.
    @Published var entries: [SSHConfigEntry] = []

    /// Aliases of entries the user has checked for import.
    @Published var selected: Set<String> = []

    /// Non-nil when a user-facing error should be displayed.
    @Published var errorMessage: String?

    /// `true` while the import is being written to the database.
    @Published var isImporting: Bool = false

    // MARK: - File picking (sandbox-safe)

    /// Opens an `NSOpenPanel` pre-pointed at `~/.ssh/config`.
    /// Falls back gracefully when the sandbox blocks direct access.
    func pickFile() {
        let panel = NSOpenPanel()
        panel.title = "Selecionar SSH Config"
        panel.message = "Escolha o arquivo de configuração SSH a importar."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        // Pre-navigate to ~/.ssh so the user does not have to hunt.
        let suggestedDir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh")
        panel.directoryURL = suggestedDir

        // Suggest the canonical config file name.
        panel.nameFieldStringValue = "config"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFile(url: url)
    }

    // MARK: - Loading

    private func loadFile(url: URL) {
        let parsed = SSHConfigParser.parse(url: url)
        if parsed.isEmpty {
            errorMessage = "Nenhum host encontrado em \(url.lastPathComponent). Verifique se o arquivo está no formato OpenSSH."
        } else {
            errorMessage = nil
        }
        entries = parsed
        // Pre-select all non-wildcard entries for convenience.
        selected = Set(parsed.map(\.alias))
    }

    // MARK: - Import

    /// Converts checked entries into `Session` objects and persists them via `SessionViewModel`.
    ///
    /// - Parameter sessionViewModel: The shared `SessionViewModel` used by the rest of the app.
    func importSelected(into sessionViewModel: SessionViewModel) {
        isImporting = true
        defer { isImporting = false }

        let toImport = entries.filter { selected.contains($0.alias) }

        for entry in toImport {
            let session = Session(
                id: UUID(),
                folderId: nil,
                name: entry.alias,
                host: entry.hostname,
                port: entry.port,
                username: entry.user
            )
            // Password is empty on import; user sets it later via the edit sheet.
            // privateKeyPath is set when Plan A (private key support) is complete.
            sessionViewModel.save(session, password: "")
        }
    }

    // MARK: - Helpers

    /// Toggles the selection state of a single entry by alias.
    func toggleSelection(alias: String) {
        if selected.contains(alias) {
            selected.remove(alias)
        } else {
            selected.insert(alias)
        }
    }

    /// Selects all currently visible entries.
    func selectAll() {
        selected = Set(entries.map(\.alias))
    }

    /// Clears all selections.
    func selectNone() {
        selected.removeAll()
    }
}
```

- [ ] **Step 2: Build check**

```bash
xcodebuild -project /Users/zeitune/src/zetssh/zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
cd /Users/zeitune/src/zetssh
git add zetssh/zetssh/Presentation/Import/SSHConfigImportViewModel.swift
git commit -m "feat(G): add SSHConfigImportViewModel"
```

---

## Task 4 — Import sheet `SSHConfigImportView`

**Files:**
- Create: `zetssh/zetssh/Presentation/Import/SSHConfigImportView.swift`

- [ ] **Step 1: Create the sheet view**

```swift
// zetssh/zetssh/Presentation/Import/SSHConfigImportView.swift
import SwiftUI

struct SSHConfigImportView: View {
    @ObservedObject var importVM: SSHConfigImportViewModel
    /// Injected from the parent so the import action can persist sessions.
    @ObservedObject var sessionVM: SessionViewModel
    /// Bound to the parent's sheet-presentation flag so the sheet can dismiss itself.
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ──────────────────────────────────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Importar SSH Config")
                        .font(.headline)
                    Text("Selecione os hosts que deseja adicionar ao ZetSSH.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // ── File picker row ─────────────────────────────────────────────
            HStack {
                Button("Escolher arquivo…") {
                    importVM.pickFile()
                }
                .controlSize(.regular)

                if !importVM.entries.isEmpty {
                    Text("\(importVM.entries.count) host(s) encontrado(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Selecionar todos") { importVM.selectAll() }
                        .controlSize(.small)
                    Button("Limpar seleção") { importVM.selectNone() }
                        .controlSize(.small)
                } else {
                    Spacer()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // ── Error banner ────────────────────────────────────────────────
            if let error = importVM.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
            }

            // ── Host list ───────────────────────────────────────────────────
            if importVM.entries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Nenhum arquivo selecionado")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(importVM.entries) { entry in
                    HStack(spacing: 10) {
                        Toggle(
                            isOn: Binding(
                                get: { importVM.selected.contains(entry.alias) },
                                set: { _ in importVM.toggleSelection(alias: entry.alias) }
                            )
                        ) {
                            EmptyView()
                        }
                        .toggleStyle(.checkbox)
                        .labelsHidden()

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.alias)
                                .fontWeight(.medium)
                            Text("\(entry.user)@\(entry.hostname):\(entry.port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let idFile = entry.identityFile {
                                Text(idFile)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }

            Divider()

            // ── Footer / action row ─────────────────────────────────────────
            HStack {
                Button("Cancelar") {
                    isPresented = false
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button {
                    importVM.importSelected(into: sessionVM)
                    isPresented = false
                } label: {
                    if importVM.isImporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        let count = importVM.selected.count
                        Text(count == 0
                             ? "Importar"
                             : "Importar \(count) \(count == 1 ? "sessão" : "sessões")")
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(importVM.selected.isEmpty || importVM.isImporting)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 480, minHeight: 380)
    }
}
```

- [ ] **Step 2: Build check**

```bash
xcodebuild -project /Users/zeitune/src/zetssh/zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
cd /Users/zeitune/src/zetssh
git add zetssh/zetssh/Presentation/Import/SSHConfigImportView.swift
git commit -m "feat(G): add SSHConfigImportView sheet"
```

---

## Task 5 — Wire into `SidebarView`

**Files:**
- Modify: `zetssh/zetssh/Presentation/Sessions/SidebarView.swift`

- [ ] **Step 1: Add state and sheet to SidebarView**

Locate the existing `@State` block near the top of `SidebarView` (where `showingAddSession` is declared) and add:

```swift
@State private var showingImportSSHConfig = false
@StateObject private var sshConfigImportVM = SSHConfigImportViewModel()
```

- [ ] **Step 2: Add the import sheet modifier**

Alongside the existing `.sheet(isPresented: $showingAddSession)` modifier, add:

```swift
.sheet(isPresented: $showingImportSSHConfig) {
    SSHConfigImportView(
        importVM: sshConfigImportVM,
        sessionVM: viewModel,
        isPresented: $showingImportSSHConfig
    )
}
```

- [ ] **Step 3: Add "Importar SSH Config…" button to the bottom toolbar**

Find the `HStack` in the sidebar footer that contains the `plus` and `minus` buttons and insert a new button between the `plus` button and `Spacer()`:

```swift
// Before (schematic):
HStack {
    Button { showingAddSession = true } label: { Image(systemName: "plus") }
    Spacer()
    Button { /* delete */ } label: { Image(systemName: "minus") }
}

// After:
HStack {
    Button { showingAddSession = true } label: { Image(systemName: "plus") }

    Button {
        showingImportSSHConfig = true
    } label: {
        Image(systemName: "square.and.arrow.down")
    }
    .help("Importar SSH Config…")

    Spacer()
    Button { /* delete */ } label: { Image(systemName: "minus") }
}
```

- [ ] **Step 4: Build check**

```bash
xcodebuild -project /Users/zeitune/src/zetssh/zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 5: Commit**

```bash
cd /Users/zeitune/src/zetssh
git add zetssh/zetssh/Presentation/Sessions/SidebarView.swift
git commit -m "feat(G): wire SSH Config Import sheet into SidebarView"
```

---

## Task 6 — Register new files in Xcode project

> Xcode requires new `.swift` files to be added to the target's compile sources. Do this via Xcode UI **or** by verifying that the `project.pbxproj` already lists them (the project uses folder references that auto-include files in some configurations).

- [ ] **Step 1: Open Xcode and verify target membership**

In Xcode's Project Navigator:
1. Select `SSHConfigEntry.swift` → File Inspector → confirm "zetssh" target is checked.
2. Repeat for `SSHConfigParser.swift`, `SSHConfigImportViewModel.swift`, `SSHConfigImportView.swift`.

If any file is missing from the target, check the box in the Target Membership panel.

- [ ] **Step 2: Final build check (clean)**

```bash
xcodebuild -project /Users/zeitune/src/zetssh/zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' clean build 2>&1 | grep -E "error:|BUILD"
```

Expected output: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit project.pbxproj if modified**

```bash
cd /Users/zeitune/src/zetssh
git add zetssh.xcodeproj/project.pbxproj
git commit -m "chore(G): register SSH Config Import files in Xcode target"
```

---

## File map summary

```
zetssh/zetssh/
├── Domain/
│   └── Models/
│       └── SSHConfigEntry.swift          ← Task 1 (new)
├── Data/
│   └── SSH/
│       └── SSHConfigParser.swift         ← Task 2 (new)
└── Presentation/
    ├── Import/
    │   ├── SSHConfigImportViewModel.swift ← Task 3 (new)
    │   └── SSHConfigImportView.swift      ← Task 4 (new)
    └── Sessions/
        └── SidebarView.swift              ← Task 5 (modified)
```

---

## Sandbox & entitlements notes

- The app is sandboxed. Reading `~/.ssh/config` **directly** (without user interaction) will be blocked by the sandbox even if the path is known.
- Using `NSOpenPanel` gives the app a user-granted security-scoped bookmark for the selected file. No entitlement changes are required for this flow.
- If a future use-case requires persistent access to `~/.ssh/config` without prompting, add the `com.apple.security.files.user-selected.read-only` entitlement and store a security-scoped bookmark via `URL.startAccessingSecurityScopedResource()`.
- The current plan deliberately avoids that complexity by opening `NSOpenPanel` every time — consistent with how other SSH clients handle sandboxed file access.

---

## Relation to other plans

| Plan | Dependency |
|------|-----------|
| Plan A — Private Key Auth | Adds `Session.privateKeyPath`. After Plan A lands, replace the `// privateKeyPath` comment in `SSHConfigImportViewModel.importSelected` with `session.privateKeyPath = entry.identityFile`. |
| This plan (G) | No hard dependency on Plan A. Imported sessions work with password auth until Plan A is complete. |
