import Foundation
import GRDB

struct SessionHistory: Identifiable, Codable, FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "sessionHistory" }

    var id: UUID
    var sessionId: UUID
    var sessionName: String
    var host: String
    var username: String
    var port: Int
    var connectedAt: Date
    var disconnectedAt: Date?
    var duration: TimeInterval?
}
