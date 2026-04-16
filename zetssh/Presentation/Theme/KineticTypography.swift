import SwiftUI

enum KineticFont {
    case display
    case headline
    case title
    case body
    case caption
    case overline
    case mono

    var font: Font {
        switch self {
        case .display:  return .system(size: 22, weight: .bold, design: .default)
        case .headline: return .system(size: 17, weight: .semibold, design: .default)
        case .title:    return .system(size: 14, weight: .semibold, design: .default)
        case .body:     return .system(size: 13, weight: .regular, design: .default)
        case .caption:  return .system(size: 11, weight: .regular, design: .default)
        case .overline: return .system(size: 10, weight: .bold, design: .default)
        case .mono:     return .system(size: 13, weight: .regular, design: .monospaced)
        }
    }

    var tracking: CGFloat {
        switch self {
        case .overline: return 1.5
        default: return 0
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .mono: return 4
        default: return 2
        }
    }
}

enum KineticFontSize: CGFloat {
    case xs = 10
    case sm = 11
    case base = 13
    case md = 14
    case lg = 17
    case xl = 20
    case xxl = 24
}
