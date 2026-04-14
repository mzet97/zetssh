import Foundation
import GRDB

struct Session: Identifiable, Hashable, Codable, FetchableRecord, PersistableRecord {
    var id: UUID
    var folderId: UUID?
    var name: String
    var host: String
    var port: Int
    var username: String
    var privateKeyPath: String?
}
