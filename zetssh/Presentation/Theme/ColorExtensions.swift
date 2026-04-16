import SwiftUI

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var intVal: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&intVal)
        let a, r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (a, r, g, b) = (255, (intVal >> 16) & 0xFF, (intVal >> 8) & 0xFF, intVal & 0xFF)
        case 8:
            (a, r, g, b) = ((intVal >> 24) & 0xFF, (intVal >> 16) & 0xFF, (intVal >> 8) & 0xFF, intVal & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
