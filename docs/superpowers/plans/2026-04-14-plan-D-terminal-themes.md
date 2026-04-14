# Terminal Themes & Fonts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Subsystem D — Terminal Themes & Fonts, providing 5 predefined color themes and a font size picker that persist in GRDB and apply live to SwiftTerm.
**Architecture:** A `TerminalProfile` GRDB model stores theme/font preferences; `ThemeRegistry` converts hex colors and applies them to `SwiftTerm.TerminalView`; `TerminalPreferencesViewModel` drives a `TerminalSettingsView` sheet triggered from the toolbar, and `makeNSView` in `TerminalView.swift` fetches and applies the active profile on startup.
**Tech Stack:** SwiftUI, GRDB 6.29.3, SwiftTerm 1.13.0, AppKit

---

## Task 1 — Create `TerminalProfile` Domain Model

**File:** `zetssh/Domain/Models/TerminalProfile.swift`

- [ ] Create the file with the struct below — it must conform to `Codable`, `FetchableRecord`, `PersistableRecord`, and `Identifiable`.

```swift
// zetssh/Domain/Models/TerminalProfile.swift
import Foundation
import GRDB

struct TerminalProfile: Identifiable, Codable, FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "terminalProfile" }

    var id: UUID
    var name: String
    var foreground: String  // hex, e.g. "#F8F8F2"
    var background: String  // hex, e.g. "#282A36"
    var cursor: String      // hex
    var fontName: String
    var fontSize: Double
    var isDefault: Bool
}
```

- [ ] Verify the file compiles:

```bash
xcodebuild -project /Users/zeitune/src/zetssh/zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] Commit:

```bash
cd /Users/zeitune/src/zetssh && git add zetssh/Domain/Models/TerminalProfile.swift && git commit -m "feat(domain): add TerminalProfile model"
```

---

## Task 2 — GRDB Migration v4: `terminalProfile` Table + Default Themes

**File:** `zetssh/Data/Database/AppDatabase.swift`

- [ ] Open `AppDatabase.swift`. After the closing brace of the `v2` migration block (line ~93), add migration `v3` as a placeholder guard if it does not exist, then add `v4`. If `v3` already exists, add only `v4`.

> **Note:** The existing migrator currently has v1 and v2. Add v3 as an empty migration (for future use) and v4 for `terminalProfile`. Insert this block inside `private var migrator: DatabaseMigrator { ... }`, right before the `return migrator` line.

```swift
        migrator.registerMigration("v3") { _ in
            // reserved for future schema changes
        }

        migrator.registerMigration("v4") { db in
            try db.create(table: "terminalProfile") { t in
                t.column("id",         .text).primaryKey()
                t.column("name",       .text).notNull()
                t.column("foreground", .text).notNull()
                t.column("background", .text).notNull()
                t.column("cursor",     .text).notNull()
                t.column("fontName",   .text).notNull()
                t.column("fontSize",   .double).notNull()
                t.column("isDefault",  .boolean).notNull().defaults(to: false)
            }

            // Insert 5 built-in themes — only one is marked isDefault = true
            let themes: [(name: String, bg: String, fg: String, cursor: String)] = [
                ("Dracula",       "#282A36", "#F8F8F2", "#F8F8F2"),
                ("Solarized Dark","#002B36", "#839496", "#839496"),
                ("One Dark",      "#282C34", "#ABB2BF", "#528BFF"),
                ("Default Dark",  "#1E1E1E", "#D4D4D4", "#D4D4D4"),
                ("Gruvbox",       "#282828", "#EBDBB2", "#EBDBB2"),
            ]

            for (index, theme) in themes.enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO terminalProfile
                            (id, name, foreground, background, cursor, fontName, fontSize, isDefault)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        UUID().uuidString,
                        theme.name,
                        theme.fg,
                        theme.bg,
                        theme.cursor,
                        "Menlo",
                        13.0,
                        index == 0 ? 1 : 0   // Dracula is the default
                    ]
                )
            }
        }
```

- [ ] The final structure of `private var migrator` must be:

```swift
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            // ... (unchanged — folder + session tables)
        }

        migrator.registerMigration("v2") { db in
            // ... (unchanged — knownHost table)
        }

        migrator.registerMigration("v3") { _ in
            // reserved for future schema changes
        }

        migrator.registerMigration("v4") { db in
            // terminalProfile table + 5 default themes (code above)
        }

        return migrator
    }
```

- [ ] Verify:

```bash
xcodebuild -project /Users/zeitune/src/zetssh/zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] Commit:

```bash
cd /Users/zeitune/src/zetssh && git add zetssh/Data/Database/AppDatabase.swift && git commit -m "feat(db): migration v4 — terminalProfile table with 5 default themes"
```

---

## Task 3 — Create `ThemeRegistry`

**File:** `zetssh/Data/Database/ThemeRegistry.swift`

- [ ] Create the file. This type is a pure namespace (`enum`) — no instances needed — exposing:
  - `color(hex:)` — converts a `#RRGGBB` string to `NSColor`
  - `apply(profile:to:)` — sets foreground, background, cursor, and font on a `SwiftTerm.TerminalView`

```swift
// zetssh/Data/Database/ThemeRegistry.swift
import AppKit
import SwiftTerm

enum ThemeRegistry {

    // MARK: - Hex → NSColor

    /// Converts a "#RRGGBB" hex string to NSColor.
    static func color(hex: String) -> NSColor {
        let stripped = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: stripped).scanHexInt64(&rgb)
        return NSColor(
            red:   CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >>  8) & 0xFF) / 255.0,
            blue:  CGFloat( rgb        & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    // MARK: - Apply Profile to TerminalView

    /// Applies all visual properties from `profile` to the given SwiftTerm TerminalView.
    /// Must be called on the main thread.
    @MainActor
    static func apply(profile: TerminalProfile, to termView: SwiftTerm.TerminalView) {
        termView.nativeForegroundColor = color(hex: profile.foreground)
        termView.nativeBackgroundColor = color(hex: profile.background)
        termView.caretColor            = color(hex: profile.cursor)

        let resolvedFont = NSFont(name: profile.fontName, size: profile.fontSize)
                        ?? NSFont.monospacedSystemFont(ofSize: profile.fontSize, weight: .regular)
        termView.font = resolvedFont
    }
}
```

- [ ] Verify:

```bash
xcodebuild -project /Users/zeitune/src/zetssh/zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] Commit:

```bash
cd /Users/zeitune/src/zetssh && git add zetssh/Data/Database/ThemeRegistry.swift && git commit -m "feat(data): ThemeRegistry with hex-to-NSColor and apply(profile:to:)"
```

---

## Task 4 — Create `TerminalPreferencesViewModel`

**File:** `zetssh/Presentation/Settings/TerminalPreferencesViewModel.swift`

- [ ] Create the `Presentation/Settings/` directory if it does not exist:

```bash
mkdir -p /Users/zeitune/src/zetssh/zetssh/Presentation/Settings
```

- [ ] Create the file:

```swift
// zetssh/Presentation/Settings/TerminalPreferencesViewModel.swift
import Foundation
import GRDB
import Combine

@MainActor
final class TerminalPreferencesViewModel: ObservableObject {

    @Published var profiles: [TerminalProfile] = []
    @Published var activeProfile: TerminalProfile?

    private let db: AppDatabase

    init(db: AppDatabase = .shared) {
        self.db = db
        Task { await load() }
    }

    // MARK: - Load

    func load() async {
        do {
            let result = try await db.dbWriter.read { db in
                try TerminalProfile.fetchAll(db)
            }
            self.profiles = result
            self.activeProfile = result.first(where: { $0.isDefault }) ?? result.first
        } catch {
            AppLogger.shared.log("TerminalPreferencesViewModel.load error: \(error)", category: .database, level: .error)
        }
    }

    // MARK: - Set Active Profile

    /// Marks `profile` as the default and clears isDefault on all others.
    func setActive(profile: TerminalProfile) {
        Task {
            do {
                try await db.dbWriter.write { db in
                    // Clear all defaults
                    try db.execute(sql: "UPDATE terminalProfile SET isDefault = 0")
                    // Set new default
                    var updated = profile
                    updated.isDefault = true
                    try updated.update(db)
                }
                await load()
            } catch {
                AppLogger.shared.log("TerminalPreferencesViewModel.setActive error: \(error)", category: .database, level: .error)
            }
        }
    }

    // MARK: - Update Font Size on Active Profile

    func updateFontSize(_ size: Double) {
        guard var profile = activeProfile else { return }
        profile.fontSize = max(8, min(size, 32))
        Task {
            do {
                try await db.dbWriter.write { db in
                    try profile.update(db)
                }
                await load()
            } catch {
                AppLogger.shared.log("TerminalPreferencesViewModel.updateFontSize error: \(error)", category: .database, level: .error)
            }
        }
    }
}
```

- [ ] Verify:

```bash
xcodebuild -project /Users/zeitune/src/zetssh/zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] Commit:

```bash
cd /Users/zeitune/src/zetssh && git add zetssh/Presentation/Settings/TerminalPreferencesViewModel.swift && git commit -m "feat(presentation): TerminalPreferencesViewModel with load/setActive/updateFontSize"
```

---

## Task 5 — Create `TerminalSettingsView`

**File:** `zetssh/Presentation/Settings/TerminalSettingsView.swift`

- [ ] Create the file. The view is a sheet containing:
  - A `LazyVGrid` of theme cards (color swatches + name + checkmark for active)
  - A font size stepper bound to the active profile's `fontSize`
  - A live preview mock (colored `RoundedRectangle` with sample text using the active theme colors)

```swift
// zetssh/Presentation/Settings/TerminalSettingsView.swift
import SwiftUI

struct TerminalSettingsView: View {

    @StateObject private var viewModel = TerminalPreferencesViewModel()
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 140), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // MARK: Header
            HStack {
                Text("Terminal Appearance")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Divider()

            // MARK: Theme Grid
            Text("Theme")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.profiles) { profile in
                    ThemeCardView(
                        profile: profile,
                        isActive: profile.id == viewModel.activeProfile?.id
                    )
                    .onTapGesture {
                        viewModel.setActive(profile: profile)
                    }
                }
            }

            Divider()

            // MARK: Font Size
            if let active = viewModel.activeProfile {
                HStack {
                    Text("Font Size")
                        .font(.headline)
                    Spacer()
                    Stepper(
                        value: Binding(
                            get: { active.fontSize },
                            set: { viewModel.updateFontSize($0) }
                        ),
                        in: 8...32,
                        step: 1
                    ) {
                        Text("\(Int(active.fontSize)) pt")
                            .monospacedDigit()
                            .frame(minWidth: 48, alignment: .trailing)
                    }
                }

                Divider()

                // MARK: Live Preview
                Text("Preview")
                    .font(.headline)

                LivePreviewView(profile: active)
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 480)
    }
}

// MARK: - Theme Card

private struct ThemeCardView: View {
    let profile: TerminalProfile
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Color swatch strip
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: profile.background))
                    .frame(height: 32)
                    .overlay(
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color(hex: profile.foreground))
                                .frame(width: 8, height: 8)
                            Circle()
                                .fill(Color(hex: profile.cursor))
                                .frame(width: 8, height: 8)
                        }
                        .padding(.leading, 6),
                        alignment: .leading
                    )
            }

            HStack {
                Text(profile.name)
                    .font(.caption)
                    .foregroundColor(.primary)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.caption)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isActive ? 2 : 1)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Live Preview

private struct LivePreviewView: View {
    let profile: TerminalProfile

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: profile.background))

            VStack(alignment: .leading, spacing: 2) {
                Text("user@host:~$ ssh admin@192.168.1.1")
                    .foregroundColor(Color(hex: profile.foreground))
                Text("Welcome to ZetSSH v1.0")
                    .foregroundColor(Color(hex: profile.foreground).opacity(0.8))
                HStack(spacing: 0) {
                    Text("$ ")
                        .foregroundColor(Color(hex: profile.foreground))
                    Rectangle()
                        .fill(Color(hex: profile.cursor))
                        .frame(width: 9, height: 16)
                }
            }
            .font(.system(size: profile.fontSize, design: .monospaced))
            .padding(12)
        }
        .frame(height: 90)
    }
}

// MARK: - Color(hex:) SwiftUI helper

private extension Color {
    init(hex: String) {
        let stripped = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: stripped).scanHexInt64(&rgb)
        self.init(
            red:   Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >>  8) & 0xFF) / 255.0,
            blue:  Double( rgb        & 0xFF) / 255.0
        )
    }
}
```

- [ ] Verify:

```bash
xcodebuild -project /Users/zeitune/src/zetssh/zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] Commit:

```bash
cd /Users/zeitune/src/zetssh && git add zetssh/Presentation/Settings/TerminalSettingsView.swift && git commit -m "feat(presentation): TerminalSettingsView with theme cards, font stepper, live preview"
```

---

## Task 6 — Wire Active Profile into `TerminalView.swift`

**File:** `zetssh/Presentation/Terminal/TerminalView.swift`

- [ ] In `makeNSView(context:)`, after the line `let termView = SwiftTerm.TerminalView(frame: .zero)`, add a synchronous GRDB read to fetch the active profile and apply it via `ThemeRegistry`. Insert the following block immediately after `termView` is created and before `termView.terminalDelegate = context.coordinator`:

```swift
        // Apply persisted terminal theme
        if let profile = try? AppDatabase.shared.dbWriter.read({ db in
            try TerminalProfile
                .filter(Column("isDefault") == true)
                .fetchOne(db)
                ?? TerminalProfile.fetchOne(db)
        }) {
            ThemeRegistry.apply(profile: profile, to: termView)
        }
```

- [ ] The updated `makeNSView` should look like:

```swift
    func makeNSView(context: Context) -> SwiftTerm.TerminalView {
        let termView = SwiftTerm.TerminalView(frame: .zero)

        // Apply persisted terminal theme
        if let profile = try? AppDatabase.shared.dbWriter.read({ db in
            try TerminalProfile
                .filter(Column("isDefault") == true)
                .fetchOne(db)
                ?? TerminalProfile.fetchOne(db)
        }) {
            ThemeRegistry.apply(profile: profile, to: termView)
        }

        termView.terminalDelegate = context.coordinator
        context.coordinator.terminalView = termView

        let password = (try? KeychainService.shared.fetchPassword(forSessionId: sessionId)) ?? ""
        let engine   = RealSSHEngine()
        engine.delegate = context.coordinator
        context.coordinator.engine   = engine
        context.coordinator.host     = host
        context.coordinator.port     = port
        context.coordinator.username = username
        context.coordinator.password = password

        return termView
    }
```

- [ ] Add `import GRDB` at the top of `TerminalView.swift` if it is not already present.

- [ ] Verify:

```bash
xcodebuild -project /Users/zeitune/src/zetssh/zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] Commit:

```bash
cd /Users/zeitune/src/zetssh && git add zetssh/Presentation/Terminal/TerminalView.swift && git commit -m "feat(terminal): apply active TerminalProfile theme on view creation"
```

---

## Task 7 — Add Toolbar Button to Open `TerminalSettingsView`

**File:** `zetssh/Presentation/Sessions/SessionDetailView.swift`

- [ ] Read the current `SessionDetailView.swift` to identify where its toolbar items are declared. Look for `.toolbar { ... }` modifier or a `ToolbarItem` block.

- [ ] Add a `@State` property for the sheet and a toolbar button. Insert these additions:

**State property** (add near top of `SessionDetailView`, alongside other `@State` properties):
```swift
    @State private var showingTerminalSettings = false
```

**Toolbar item** (inside the `.toolbar { }` block — add a new `ToolbarItem`):
```swift
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingTerminalSettings = true
                    } label: {
                        Label("Terminal Appearance", systemImage: "paintpalette")
                    }
                    .help("Configure terminal theme and font")
                }
```

**Sheet modifier** (add to the view's modifier chain, after the `.toolbar { }` block):
```swift
        .sheet(isPresented: $showingTerminalSettings) {
            TerminalSettingsView()
        }
```

- [ ] Verify:

```bash
xcodebuild -project /Users/zeitune/src/zetssh/zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] Commit:

```bash
cd /Users/zeitune/src/zetssh && git add zetssh/Presentation/Sessions/SessionDetailView.swift && git commit -m "feat(ui): toolbar button to open TerminalSettingsView sheet"
```

---

## Task 8 — Add New Files to Xcode Project

> **Important:** New `.swift` files created outside Xcode are not automatically added to the build target. They must be referenced in `zetssh.xcodeproj/project.pbxproj`.

- [ ] Open Xcode, select the `zetssh` target, and manually add the following files using **File > Add Files to "zetssh"**:
  - `zetssh/Domain/Models/TerminalProfile.swift`
  - `zetssh/Data/Database/ThemeRegistry.swift`
  - `zetssh/Presentation/Settings/TerminalPreferencesViewModel.swift`
  - `zetssh/Presentation/Settings/TerminalSettingsView.swift`

  Alternatively, use `xcodebuild` to verify compilation already succeeds (if the files were added as part of a directory group that Xcode picks up automatically), or use the following to confirm inclusion:

```bash
grep -l "TerminalProfile\|ThemeRegistry\|TerminalPreferencesViewModel\|TerminalSettingsView" /Users/zeitune/src/zetssh/zetssh.xcodeproj/project.pbxproj
```

- [ ] If the grep returns nothing, add the files to the `project.pbxproj` manually in Xcode or via `xcodebuild` script. After adding in Xcode, re-run:

```bash
xcodebuild -project /Users/zeitune/src/zetssh/zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` with zero errors.

- [ ] Commit the updated `project.pbxproj`:

```bash
cd /Users/zeitune/src/zetssh && git add zetssh.xcodeproj/project.pbxproj && git commit -m "chore(xcode): add TerminalProfile, ThemeRegistry, Settings views to build target"
```

---

## Task 9 — Final Integration Smoke Test

- [ ] Clean build from scratch:

```bash
xcodebuild -project /Users/zeitune/src/zetssh/zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' clean build 2>&1 | grep -E "error:|warning:|BUILD"
```

Expected output contains `BUILD SUCCEEDED`. Zero `error:` lines.

- [ ] Manual run checklist (perform in the running app):
  1. Launch ZetSSH. Open any saved session detail view.
  2. Verify the terminal background is Dracula (`#282A36`) by default — no plain white/black terminal.
  3. Click the paintpalette toolbar button. The `TerminalSettingsView` sheet opens.
  4. Click "Solarized Dark" theme card. A checkmark appears on it.
  5. Dismiss the sheet and reconnect (or open a new session). The terminal background changes to `#002B36`.
  6. Open settings again, adjust font size stepper from 13 to 16. Live preview updates instantly.
  7. Dismiss and reconnect. Font size is 16 pt.
  8. Quit and relaunch the app. The last selected theme and font size persist.

- [ ] Commit any final fixes, then tag:

```bash
cd /Users/zeitune/src/zetssh && git tag subsystem-D-terminal-themes
```

---

## File Map Summary

| File | Location | Role |
|------|----------|------|
| `TerminalProfile.swift` | `zetssh/Domain/Models/` | GRDB model — theme + font properties |
| `AppDatabase.swift` | `zetssh/Data/Database/` | Migration v3 (placeholder) + v4 (table + 5 themes) |
| `ThemeRegistry.swift` | `zetssh/Data/Database/` | Static hex→NSColor + `apply(profile:to:)` |
| `TerminalPreferencesViewModel.swift` | `zetssh/Presentation/Settings/` | `@MainActor ObservableObject` — load / setActive / updateFontSize |
| `TerminalSettingsView.swift` | `zetssh/Presentation/Settings/` | Sheet UI — theme grid + stepper + live preview |
| `TerminalView.swift` | `zetssh/Presentation/Terminal/` | Fetch + apply active profile in `makeNSView` |
| `SessionDetailView.swift` | `zetssh/Presentation/Sessions/` | Toolbar button + sheet trigger |

---

## Key Constraints & Notes

- `ThemeRegistry.apply(profile:to:)` is `@MainActor` — always called from the main thread (`makeNSView` runs on main; settings sheet runs on main).
- `isDefault` uses `Int` in SQLite (0/1); Swift `Bool` auto-maps via GRDB's `Codable` bridge.
- The `Color(hex:)` SwiftUI extension is private to `TerminalSettingsView.swift` to avoid conflicts. `ThemeRegistry.color(hex:)` returns `NSColor` for the SwiftTerm AppKit API.
- Migration `v3` is registered as an empty placeholder to keep version numbering consistent with any parallel feature branches targeting v3.
- Font fallback: if `profile.fontName` is not installed (e.g., "JetBrains Mono" absent), `ThemeRegistry` falls back to `NSFont.monospacedSystemFont` — never crashes.
- Stepper clamps font size to `8...32` pt in both the ViewModel and the Stepper binding `in:` range.
