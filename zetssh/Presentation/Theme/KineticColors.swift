import SwiftUI

enum KineticColors {
    // MARK: - Surfaces

    static let surface = Color(hex: "131313")
    static let surfaceDim = Color(hex: "131313")
    static let surfaceContainerLowest = Color(hex: "0e0e0e")
    static let surfaceContainerLow = Color(hex: "1b1b1c")
    static let surfaceContainer = Color(hex: "202020")
    static let surfaceContainerHigh = Color(hex: "2a2a2a")
    static let surfaceContainerHighest = Color(hex: "353535")
    static let surfaceBright = Color(hex: "393939")
    static let surfaceVariant = Color(hex: "353535")

    // MARK: - Primary

    static let primary = Color(hex: "adc6ff")
    static let primaryContainer = Color(hex: "4b8eff")
    static let onPrimary = Color(hex: "002e69")
    static let primaryFixed = Color(hex: "d8e2ff")
    static let primaryFixedDim = Color(hex: "adc6ff")
    static let onPrimaryFixed = Color(hex: "001a41")
    static let onPrimaryFixedVariant = Color(hex: "004493")

    // MARK: - Secondary

    static let secondary = Color(hex: "c6c6cb")
    static let secondaryContainer = Color(hex: "48494d")
    static let onSecondary = Color(hex: "2f3034")
    static let onSecondaryContainer = Color(hex: "b8b8bd")
    static let secondaryFixed = Color(hex: "e3e2e7")
    static let secondaryFixedDim = Color(hex: "c6c6cb")

    // MARK: - Tertiary

    static let tertiary = Color(hex: "ffb595")
    static let tertiaryContainer = Color(hex: "ef6719")
    static let onTertiary = Color(hex: "571e00")
    static let tertiaryFixed = Color(hex: "ffdbcc")
    static let tertiaryFixedDim = Color(hex: "ffb595")

    // MARK: - Error

    static let error = Color(hex: "ffb4ab")
    static let errorContainer = Color(hex: "93000a")
    static let onError = Color(hex: "690005")
    static let onErrorContainer = Color(hex: "ffdad6")

    // MARK: - Text

    static let onSurface = Color(hex: "e5e2e1")
    static let onSurfaceVariant = Color(hex: "c1c6d7")
    static let onBackground = Color(hex: "e5e2e1")

    // MARK: - Outlines

    static let outline = Color(hex: "8b90a0")
    static let outlineVariant = Color(hex: "414755")

    // MARK: - Inverse

    static let inverseSurface = Color(hex: "e5e2e1")
    static let inverseOnSurface = Color(hex: "303030")
    static let inversePrimary = Color(hex: "005bc1")

    // MARK: - macOS Traffic Lights

    static let macTrafficRed = Color(hex: "ff5f57")
    static let macTrafficYellow = Color(hex: "febc2e")
    static let macTrafficGreen = Color(hex: "28c840")

    // MARK: - Derived

    static let ghostBorder = outlineVariant.opacity(0.15)
    static let primaryGradient = LinearGradient(
        colors: [primary, primaryContainer],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}


