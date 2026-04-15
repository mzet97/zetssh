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
