import SwiftUI

struct KineticButton: View {
    enum Style {
        case primary
        case ghost
        case destructive
    }

    let title: String
    let icon: String?
    let style: Style
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        style: Style = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                }
                Text(title)
                    .font(KineticFont.body.font)
                    .fontWeight(style == .primary ? .semibold : .medium)
            }
            .padding(.horizontal, style == .ghost ? 12 : 20)
            .padding(.vertical, 8)
            .frame(minWidth: style == .ghost ? 0 : 80)
            .background(background)
            .foregroundColor(foreground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            KineticColors.primaryGradient
                .cornerRadius(8)
                .shadow(color: KineticColors.primaryContainer.opacity(0.2), radius: 4, y: 2)
        case .ghost:
            KineticColors.primary
                .opacity(0)
        case .destructive:
            KineticColors.errorContainer
                .opacity(0.3)
                .cornerRadius(8)
        }
    }

    private var foreground: Color {
        switch style {
        case .primary: KineticColors.onPrimary
        case .ghost: KineticColors.primary
        case .destructive: KineticColors.error
        }
    }
}
