import SwiftUI

struct AboutSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(KineticColors.primary)

                Text("ZetSSH")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(KineticColors.onSurface)

                Text("Secure Shell Client")
                    .font(KineticFont.overline.font)
                    .tracking(KineticFont.overline.tracking)
                    .foregroundStyle(KineticColors.onSurfaceVariant)
            }
            .padding(.top, 32)

            // Info cards
            VStack(spacing: 0) {
                infoRow(label: "Version", value: "1.0.0")
                GhostDivider()
                infoRow(label: "Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                GhostDivider()
                infoRow(label: "Protocol", value: "SSH-2.0")
                GhostDivider()
                infoRow(label: "Encryption", value: "AES-256-GCM")
                GhostDivider()
                infoRow(label: "Engine", value: "SwiftNIO-SSH")
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(KineticColors.surfaceContainerLow)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 32)

            // Credits
            VStack(spacing: 4) {
                Text("Built with SwiftUI + SwiftTerm")
                    .font(KineticFont.caption.font)
                    .foregroundStyle(KineticColors.onSurfaceVariant)
                Text("Persistência: GRDB + SQLCipher")
                    .font(KineticFont.caption.font)
                    .foregroundStyle(KineticColors.onSurfaceVariant)
            }

            Spacer()

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 20)
        }
        .frame(width: 400, height: 420)
        .background(KineticColors.surface)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(KineticFont.caption.font)
                .foregroundStyle(KineticColors.onSurfaceVariant)
            Spacer()
            Text(value)
                .font(KineticFont.caption.font)
                .fontWeight(.medium)
                .foregroundStyle(KineticColors.onSurface)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
