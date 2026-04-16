import SwiftUI

struct GhostDivider: View {
    var vertical: Bool = false

    var body: some View {
        if vertical {
            KineticColors.outlineVariant
                .opacity(0.15)
                .frame(width: 1)
        } else {
            KineticColors.outlineVariant
                .opacity(0.15)
                .frame(height: 1)
        }
    }
}
