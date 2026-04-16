import SwiftUI

struct KineticInputField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var showFocusAccent: Bool = true

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .focused($isFocused)
                } else {
                    TextField(placeholder, text: $text)
                        .focused($isFocused)
                }
            }
            .textFieldStyle(.plain)
            .font(KineticFont.body.font)
            .foregroundStyle(KineticColors.onSurface)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(KineticColors.surfaceContainerHighest.opacity(0.5))
            )

            if showFocusAccent {
                GeometryReader { geo in
                    KineticColors.primary
                        .frame(height: 2)
                        .frame(width: isFocused ? geo.size.width : 0)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .animation(.easeInOut(duration: 0.25), value: isFocused)
                }
                .frame(height: 2)
            }
        }
    }
}
