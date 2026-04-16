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


