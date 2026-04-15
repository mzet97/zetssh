import XCTest
import GRDB
@testable import zetssh

@MainActor
final class SessionViewModelTests: XCTestCase {

    func testSaveAndDeleteSession() throws {
        let db = try makeTestDatabase()
        let session = Session(id: UUID(), folderId: nil, name: "Test",
                              host: "test.local", port: 22, username: "u",
                              privateKeyPath: nil)
        try db.write { d in try session.save(d) }
        let count1 = try db.read { d in try Session.fetchCount(d) }
        XCTAssertEqual(count1, 1)

        try db.write { d in try session.delete(d) }
        let count2 = try db.read { d in try Session.fetchCount(d) }
        XCTAssertEqual(count2, 0)
    }

    func testMultipleSessionsSaved() throws {
        let db = try makeTestDatabase()
        for i in 1...3 {
            let s = Session(id: UUID(), folderId: nil, name: "S\(i)",
                            host: "h\(i).com", port: 22, username: "u\(i)",
                            privateKeyPath: nil)
            try db.write { d in try s.save(d) }
        }
        let all = try db.read { d in try Session.fetchAll(d) }
        XCTAssertEqual(all.count, 3)
    }
}
