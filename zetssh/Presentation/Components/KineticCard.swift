import SwiftUI

struct KineticCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = 20

    @State private var isHovered = false

    init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovered ? KineticColors.surfaceContainer : KineticColors.surfaceContainerLow)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(isHovered ? 0.99 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
