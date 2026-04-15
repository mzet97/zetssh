import Foundation
import GRDB

final class SessionRepository {
    init() {}
    
    func fetchAll() throws -> [Session] {
        try AppDatabase.shared.dbWriter.read { db in
            try Session.fetchAll(db)
        }
    }
    
    func save(_ session: inout Session) throws {
        try AppDatabase.shared.dbWriter.write { db in
            try session.save(db)
        }
    }
    
    @discardableResult
    func delete(_ session: Session) throws -> Bool {
        try AppDatabase.shared.dbWriter.write { db in
            try session.delete(db)
        }
    }
}
