import Foundation
import GRDB

struct KnownHost: Codable, FetchableRecord, PersistableRecord, Equatable {
    var host: String
    var port: Int
    var algorithm: String    // ex: "ssh-ed25519", "ecdsa-sha2-nistp256"
    var fingerprint: String  // SHA256 hex da representação da chave pública
    var addedAt: Date

    static var databaseTableName: String { "knownHost" }
}
