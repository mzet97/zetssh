# UI Overhaul: Stitch "Kinetic Command" Design System

## Overview

Migrate ZetSSH from the current standard SwiftUI interface to the "Kinetic Command / Digital Artisan" design system defined in `stitch_native_macos_ssh_client/`. The new design features a dark obsidian theme, no-border philosophy, glass morphism, gradient accents, and a professional terminal-centric layout.

## Source Material

- `stitch_native_macos_ssh_client/cupertino_terminal/DESIGN.md` — Design system tokens & rules
- `stitch_native_macos_ssh_client/ssh_terminal_principal/code.html` — Main terminal layout
- `stitch_native_macos_ssh_client/nova_conex_o_ssh/code.html` — New Connection modal
- `stitch_native_macos_ssh_client/servidores_favoritos/code.html` — Favorites grid
- `stitch_native_macos_ssh_client/hist_rico_de_sess_es/code.html` — Session history table
- `stitch_native_macos_ssh_client/gerenciador_de_chaves_ssh/code.html` — SSH key manager
- `stitch_native_macos_ssh_client/configura_es_do_aplicativo/code.html` — Settings

## Architecture

New files go under `zetssh/Presentation/` following existing MVVM + Clean Architecture. A shared design token layer ensures consistency across all screens.

---

## Phase 1: Design System Foundation

**Goal**: Create the shared design tokens and base components that all screens will consume.

### 1.1 Color Tokens — `Presentation/Theme/KineticColors.swift`

Map all Stitch Tailwind colors to SwiftUI Color extensions:

| Token | Hex | Usage |
|---|---|---|
| `surface` | `#131313` | Window base |
| `surfaceContainerLow` | `#1b1b1c` | Sidebar, secondary panels |
| `surfaceContainer` | `#202020` | Terminal workspace |
| `surfaceContainerHigh` | `#2a2a2a` | Hover states |
| `surfaceContainerHighest` | `#353535` | Popovers, modals |
| `surfaceContainerLowest` | `#0e0e0e` | Deepest blacks |
| `primary` | `#adc6ff` | Active elements, links |
| `primaryContainer` | `#4b8eff` | Gradient endpoint |
| `onSurface` | `#e5e2e1` | Primary text |
| `onSurfaceVariant` | `#c1c6d7` | Secondary text, labels |
| `outline` | `#8b90a0` | Dividers (ghost borders only) |
| `outlineVariant` | `#414755` | Ghost borders at 15% opacity |
| `tertiary` | `#ffb595` | Accent highlights |
| `tertiaryContainer` | `#ef6719` | Warm accents |
| `error` | `#ffb4ab` | Error/danger states |
| `errorContainer` | `#93000a` | Error backgrounds |

### 1.2 Typography — `Presentation/Theme/KineticTypography.swift`

- UI font: Inter (already used in Stitch). Fall back to SF Pro if Inter unavailable.
- Terminal font: SF Mono / JetBrains Mono (existing SwiftTerm config)
- Define `KineticFont` enum with cases: display, headline, body, label, mono

### 1.3 Base Components — `Presentation/Components/`

| Component | File | Description |
|---|---|---|
| `KineticButton` | `KineticButton.swift` | Primary (gradient fill), Tertiary (ghost), Text-only variants |
| `GlassPanel` | `GlassPanel.swift` | `surfaceVariant` at 70% opacity + `blur(20px)` backdrop |
| `KineticInputField` | `KineticInputField.swift` | No border, `surfaceContainerHighest` bg, 2px primary bottom accent on focus |
| `KineticCard` | `KineticCard.swift` | `surfaceContainerLow` bg, `xl` radius, hover → `surfaceContainer` |
| `NavigationSidebar` | `NavigationSidebar.swift` | Brand identity, nav anchors, active connections list, profile section |
| `TopNavBar` | `TopNavBar.swift` | Tab bar (Terminals/Keys/Settings), search field, action buttons |
| `KineticTabBar` | `KineticTabBar.swift` | Active tab: `surfaceContainer` bg + blue dot. Inactive: transparent. |
| `GhostDivider` | `GhostDivider.swift` | `outlineVariant` at 15% opacity (replaces all standard Dividers) |

### 1.4 Scene-level Window Styling — `zetsshApp.swift`

- Change `WindowGroup` to use `.windowStyle(.hiddenTitleBar)` or custom titlebar
- Apply `KineticColors.surface` as default background
- Enable vibrancy for glass effects

---

## Phase 2: Navigation Shell

**Goal**: Replace the current `NavigationSplitView` with the Stitch sidebar + top nav layout.

### 2.1 Sidebar Rewrite — `Presentation/Sessions/SidebarView.swift`

Replace the current `List(selection:)` sidebar with:

```
┌──────────────────────┐
│ ● ● ●  (traffic      │
│         lights)       │
│                      │
│ Kinetic Command      │
│ DIGITAL ARTISAN      │
│                      │
│ ▸ Hosts      (active) │
│   Favorites          │
│   History             │
│                      │
│ ACTIVE CONNECTIONS   │
│ ● prod-cluster-01    │
│ ○ staging-api-v2     │
│ ● backup-node-us     │
│                      │
│ ─────────────────── │
│ [+ New Session]      │
│ [avatar] User        │
└──────────────────────┘
```

- Selection drives the main content area (Hosts list, Favorites grid, History table)
- Active connections section shows live connection status (green dot = connected, grey = disconnected)
- Uses `NavigationSidebar` component from Phase 1

### 2.2 Top Navigation Bar — New `TopNavBar.swift`

```
┌─────────────────────────────────────────────────────────────┐
│ Kinetic Command  │ Terminals  Keys  Settings │ [search] [+] │
└─────────────────────────────────────────────────────────────┘
```

- `Terminals` / `Keys` / `Settings` are mutually exclusive tab-like navigation
- Each tab changes the main content area
- Search field: `surfaceContainerHighest/40` bg, rounded, search icon
- Action buttons: add, split screen, info
- Connect button: gradient `primary` → `primaryContainer`

### 2.3 Main Content Routing — `ContentView.swift`

Replace current `NavigationSplitView` with:

```
HStack {
    NavigationSidebar(selection: $navSelection)
    VStack {
        TopNavBar(tab: $activeTab)
        KineticTabBar(tabsVM:)     // only when activeTab == .terminals
        mainContent                // switches on navSelection + activeTab
    }
}
```

### 2.4 Tab Bar Redesign — `TabBarView.swift`

- Active tab: `surfaceContainer` bg, rounded top corners, blue 4px dot next to label
- Inactive tab: transparent, hover → `surfaceContainerLow`
- Close button visible on hover only
- New tab `+` button at end

---

## Phase 3: Core Screens

### 3.1 Hosts Screen (default sidebar selection)

Reuses the existing `SessionDetailView` with `SSHTerminalView` but with:
- Dark `surfaceContainer` background
- Connection metadata overlay (top-right, low opacity): session ID, uptime, IP
- "Encrypted Tunnel Active" glass badge (bottom-right, dismissible)

### 3.2 New Connection Modal — Rewrite `SessionFormView.swift`

Transform from standard `Form` to glass modal:

```
┌─────────────────────────────────────────┐
│ ● ● ●    New Connection                 │
│─────────────────────────────────────────│
│                                         │
│ Name        [                    ]      │
│                                         │
│ Remote Host [              ] Port [22]  │
│                                         │
│ Username    [                    ]      │
│                                         │
│ Method      [Key File] [Password]       │
│                                         │
│     ┌──────────────────────────┐        │
│     │    🔑                    │        │
│     │  Select Private Key      │        │
│     │  Drop .pem or .pub here  │        │
│     └──────────────────────────┘        │
│                                         │
│ ☐ Save to Keychain    [Cancel] [Connect]│
└─────────────────────────────────────────┘
```

- Glass panel with `mac-shadow` (0 20px 40px rgba(0,0,0,0.6))
- Mac traffic light buttons in header
- Drag-and-drop zone for private key files
- Key File / Password toggle as pill buttons
- Connect button uses gradient

### 3.3 Favorites Screen — New `Presentation/Sessions/FavoritesView.swift`

- Folder sections with headers (e.g., "Production Clusters", "Side Projects")
- Server cards in 3-column grid: icon, name, IP, status badge, last accessed
- Status badges: Critical (red), Active (blue), Stable (grey), Offline (grey)
- "Add New Host" dashed placeholder card
- Detail sidebar (xl screens only): server image, SSH command, metrics (CPU, Memory), quick actions (Shell, SFTP, Stats, Reboot)

### 3.4 Session History Screen — New `Presentation/Sessions/HistoryView.swift`

- Table view: Host name, Address, Date/Time, Duration, Actions
- Actions visible on hover: View Logs, Reconnect
- Filter dropdown ("All Connections")
- Footer bar: active sessions count, total entries, log size
- Analytics sidebar (lg screens): Most Frequent Host, Total Uptime, visual activity card
- "End-to-End Encrypted" glass badge at bottom

---

## Phase 4: Advanced Screens

### 4.1 Key Management — New `Presentation/Keys/`

When "Keys" tab is active in top nav:

```
┌──────────────┬──────────────────────────────────────────┐
│ SSH Keys      │ 🔑 id_ed25519_prod                      │
│               │ Created Oct 24, 2023 • Last used 2h ago  │
│ [search]      │                                          │
│               │ Fingerprint (SHA256)                     │
│ > id_ed25519  │ ┌────────────────────────────────────┐   │
│   staging-web │ │ SHA256:3u8j29...w0m2x              │   │
│   ci-deploy   │ └────────────────────────────────────┘   │
│   legacy-db   │                                          │
│               │ Key Type: Ed25519  │  Size: 256 Bits     │
│               │                                          │
│               │ Public Key Content                       │
│               │ ┌────────────────────────────────────┐   │
│               │ │ ssh-ed25519 AAAAC3Nza...           │   │
│               │ └────────────────────────────────────┘   │
│               │                                          │
│               │ [14 Servers] [Never] [Encrypted]          │
│               │                    [Import] [Add Key]     │
└──────────────┴──────────────────────────────────────────┘
```

- Left: searchable key list with name + type badge
- Right: detail view with fingerprint, metadata grid, public key preview, usage stats
- FAB: Import from File, Add Key (opens generate modal)

### 4.2 Settings Overhaul — Rewrite `Presentation/Settings/`

When "Settings" tab is active:

- Left category rail: General, Terminal, Shortcuts, Advanced
- Main scrollable canvas with sections

Sections:
- **General**: Cloud Sync toggle, Terminal Notifications toggle
- **Terminal Appearance**: Theme preview card, font size slider, cursor style picker (Block/Beam/Underline), background blur slider
- **Keyboard Shortcuts**: shortcut list with keyboard badge UI
- **Advanced**: SSH Agent Forwarding toggle, Keepalive Interval field, Danger Zone (Clear History, Reset Config)
- **Status bar** at bottom: sync status, SSH version, build number

---

## Phase 5: Polish & Animation

### 5.1 Transitions
- Sidebar nav hover: `surfaceContainerHigh` with 0.5s ease-in-out
- Card hover: subtle scale(0.99) + bg shift
- Tab switch: cross-dissolve between content areas
- Modal appear: fade + scale from 0.95

### 5.2 SF Symbols
- Use thin/light weight to match Inter typography scale
- Specific icons: `dns`, `star`, `history`, `terminal`, `key`, `add`, `close`, `search`, `shield`

### 5.3 Accessibility
- Ghost border fallback: `outlineVariant` at 15% opacity for container definition
- Ensure all interactive elements have proper focus rings
- Dynamic type support for UI text (terminal remains fixed-size)

---

## Implementation Order

| Step | Files | Depends On | Estimated Complexity |
|---|---|---|---|
| 1.1 | `Theme/KineticColors.swift` | — | Low |
| 1.2 | `Theme/KineticTypography.swift` | 1.1 | Low |
| 1.3a | `Components/KineticButton.swift` | 1.1 | Low |
| 1.3b | `Components/GlassPanel.swift` | 1.1 | Low |
| 1.3c | `Components/KineticInputField.swift` | 1.1 | Low |
| 1.3d | `Components/KineticCard.swift` | 1.1 | Low |
| 1.3e | `Components/GhostDivider.swift` | 1.1 | Low |
| 2.1 | `Sessions/SidebarView.swift` (rewrite) | 1.3 | High |
| 2.2 | `Components/TopNavBar.swift` | 1.1, 1.2 | Medium |
| 2.3 | `ContentView.swift` (rewrite) | 2.1, 2.2 | High |
| 2.4 | `Sessions/TabBarView.swift` (rewrite) | 1.1 | Medium |
| 3.1 | Terminal metadata overlay | 1.3b | Low |
| 3.2 | `Sessions/SessionFormView.swift` (rewrite) | 1.3 | High |
| 3.3 | `Sessions/FavoritesView.swift` (new) | 1.3d | High |
| 3.4 | `Sessions/HistoryView.swift` (new) | 1.3 | High |
| 4.1 | `Keys/` (new directory) | 1.3 | High |
| 4.2 | `Settings/` (rewrite) | 1.3 | High |
| 5.x | Polish pass | all above | Medium |

## Key Constraints

1. **No breaking changes to business logic** — Only Presentation layer changes. Domain and Data layers untouched.
2. **Preserve existing functionality** — All current features (sessions, tabs, SFTP, import) must work identically.
3. **SwiftUI only** — No AppKit for UI (only the existing SwiftTerm NSViewRepresentable).
4. **macOS 14+** — Target minimum stays macOS 14.0 (Sonoma).
5. **Design system consistency** — Every new view/component must use KineticColors and KineticTypography. No hardcoded colors.
