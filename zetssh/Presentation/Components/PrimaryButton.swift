import SwiftUI

public struct PrimaryButton: View {
    public let title: String
    public let action: () -> Void
    public var isDisabled: Bool = false
    
    public init(title: String, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isDisabled = isDisabled
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(8)
                .foregroundColor(.white)
                .background(isDisabled ? Color.gray : Color.accentColor)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
