import Foundation
import GRDB

struct TerminalProfile: Identifiable, Codable, FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "terminalProfile" }

    var id: UUID
    var name: String
    var foreground: String  // hex, e.g. "#F8F8F2"
    var background: String  // hex, e.g. "#282A36"
    var cursor: String      // hex
    var fontName: String
    var fontSize: Double
    var isDefault: Bool
}
