import Foundation
import GRDB

struct Folder: Identifiable, Hashable, Codable, FetchableRecord, PersistableRecord {
    var id: UUID
    var name: String
    var icon: String?
}
