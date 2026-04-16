import SwiftUI

struct SettingsView: View {
    enum SettingsCategory: String, CaseIterable {
        case general = "General"
        case terminal = "Terminal"
        case shortcuts = "Shortcuts"
        case advanced = "Advanced"

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .terminal: return "terminal"
            case .shortcuts: return "keyboard"
            case .advanced: return "slider.horizontal.3"
            }
        }
    }

    @State private var selectedCategory: SettingsCategory = .general
    @State private var notificationsEnabled = true
    @State private var keepaliveInterval = 30
    @State private var agentForwarding = false

    var body: some View {
        HStack(spacing: 0) {
            categoryRail
            GhostDivider(vertical: true)
            settingsCanvas
        }
        .background(KineticColors.surface)
    }

    private var categoryRail: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsCategory.allCases, id: \.self) { category in
                let isSelected = selectedCategory == category

                HStack(spacing: 10) {
                    Image(systemName: category.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(isSelected ? KineticColors.primary : KineticColors.onSurfaceVariant)
                    Text(category.rawValue)
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? KineticColors.primary : KineticColors.onSurfaceVariant)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? KineticColors.surfaceContainer : .clear)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = category
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 180)
        .background(KineticColors.surfaceContainerLow)
    }

    @ViewBuilder
    private var settingsCanvas: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                switch selectedCategory {
                case .general:
                    generalSection
                case .terminal:
                    terminalSection
                case .shortcuts:
                    shortcutsSection
                case .advanced:
                    advancedSection
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .background(KineticColors.surface)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("General", subtitle: "Application behavior and preferences. All data stored locally.")

            settingsCard {
                toggleRow(
                    icon: "bell",
                    iconColor: KineticColors.tertiary,
                    title: "Terminal Notifications",
                    subtitle: "Alert when long-running tasks finish",
                    isOn: $notificationsEnabled
                )
            }
        }
    }

    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Terminal Appearance", subtitle: "Customize your workspace.")

            settingsCard {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Theme")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(KineticColors.onSurface)
                        Text("Current: Obsidian Dusk")
                            .font(.system(size: 11))
                            .foregroundStyle(KineticColors.onSurfaceVariant)
                    }
                    Spacer()
                    Text("OBSIDIAN DUSK")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(KineticColors.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(KineticColors.primary.opacity(0.2))
                        )
                }
                .padding(16)

                GhostDivider()

                HStack {
                    Text("Font Size")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(KineticColors.onSurface)
                    Spacer()
                    Stepper(value: $keepaliveInterval, in: 8...32, step: 1) {
                        Text("\(keepaliveInterval) pt")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(KineticColors.onSurfaceVariant)
                    }
                }
                .padding(16)

                GhostDivider()

                HStack {
                    Text("Cursor Style")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(KineticColors.onSurface)
                    Spacer()
                    HStack(spacing: 8) {
                        cursorOption("Block", isSelected: true)
                        cursorOption("Beam", isSelected: false)
                        cursorOption("Underline", isSelected: false)
                    }
                }
                .padding(16)
            }
        }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Keyboard Shortcuts", subtitle: "Quick access to common actions.")

            settingsCard {
                shortcutRow("New Session", shortcut: "⌘ N")
                GhostDivider()
                shortcutRow("Close Tab", shortcut: "⌘ W")
                GhostDivider()
                shortcutRow("Toggle Sidebar", shortcut: "⌘ S")
                GhostDivider()
                shortcutRow("Open SFTP", shortcut: "⌘ ⇧ F")
                GhostDivider()
                shortcutRow("Disconnect", shortcut: "⌘ D")
            }
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Advanced", subtitle: "Power user settings.")

            settingsCard {
                toggleRow(
                    icon: "arrow.triangle.branch",
                    iconColor: KineticColors.primary,
                    title: "SSH Agent Forwarding",
                    subtitle: "Forward authentication requests to local agent",
                    isOn: $agentForwarding
                )
                GhostDivider()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Keepalive Interval")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(KineticColors.onSurface)
                        Text("Seconds between keepalive packets")
                            .font(.system(size: 11))
                            .foregroundStyle(KineticColors.onSurfaceVariant)
                    }
                    Spacer()
                    Stepper(value: $keepaliveInterval, in: 10...120, step: 5) {
                        Text("\(keepaliveInterval)s")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(KineticColors.onSurfaceVariant)
                    }
                }
                .padding(16)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Danger Zone")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(KineticColors.error)

                settingsCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Clear Connection History")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(KineticColors.onSurface)
                            Text("Permanently delete all connection logs")
                                .font(.system(size: 11))
                                .foregroundStyle(KineticColors.onSurfaceVariant)
                        }
                        Spacer()
                        KineticButton("Clear", style: .destructive) {}
                    }
                    .padding(16)
                }
            }

            statusBar
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(KineticColors.onSurface)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(KineticColors.onSurfaceVariant)
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(KineticColors.surfaceContainerLow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func toggleRow(icon: String, iconColor: Color, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor.opacity(0.1))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KineticColors.onSurface)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(KineticColors.onSurfaceVariant)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(16)
    }

    private func shortcutRow(_ action: String, shortcut: String) -> some View {
        HStack {
            Text(action)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(KineticColors.onSurface)
            Spacer()
            Text(shortcut)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(KineticColors.onSurfaceVariant)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(KineticColors.surfaceContainerHighest)
                )
        }
        .padding(16)
    }

    private func cursorOption(_ name: String, isSelected: Bool) -> some View {
        Text(name)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isSelected ? KineticColors.primary : KineticColors.onSurfaceVariant)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? KineticColors.surfaceContainerHighest : .clear)
            )
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(KineticColors.primary)
                .frame(width: 6, height: 6)
            Text("v1.0.0")
                .font(.system(size: 11))
                .foregroundStyle(KineticColors.onSurfaceVariant)
            Text("SSH-2.0")
                .font(.system(size: 11))
                .foregroundStyle(KineticColors.onSurfaceVariant)
        }
        .padding(.top, 8)
    }
}
