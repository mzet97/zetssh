import XCTest
import GRDB
@testable import zetssh

final class SessionTests: XCTestCase {

    var db: DatabaseWriter!

    override func setUp() async throws {
        db = try makeTestDatabase()
    }

    func testSessionSaveAndFetch() throws {
        let session = Session(id: UUID(), folderId: nil, name: "Prod",
                              host: "192.168.1.1", port: 22, username: "ubuntu",
                              privateKeyPath: nil)
        try db.write { d in try session.save(d) }
        let fetched = try db.read { d in try Session.fetchOne(d) }
        XCTAssertEqual(fetched?.host, "192.168.1.1")
        XCTAssertEqual(fetched?.username, "ubuntu")
    }

    func testSessionDefaultPort() throws {
        let session = Session(id: UUID(), folderId: nil, name: "Dev",
                              host: "dev.local", port: 22, username: "admin",
                              privateKeyPath: nil)
        XCTAssertEqual(session.port, 22)
    }

    func testSessionDelete() throws {
        let session = Session(id: UUID(), folderId: nil, name: "Temp",
                              host: "temp.host", port: 2222, username: "user",
                              privateKeyPath: nil)
        try db.write { d in try session.save(d) }
        try db.write { d in try session.delete(d) }
        let count = try db.read { d in try Session.fetchCount(d) }
        XCTAssertEqual(count, 0)
    }

    func testSessionWithPrivateKeyPath() throws {
        let session = Session(id: UUID(), folderId: nil, name: "KeyAuth",
                              host: "key.host", port: 22, username: "user",
                              privateKeyPath: "/Users/test/.ssh/id_ed25519")
        try db.write { d in try session.save(d) }
        let fetched = try db.read { d in try Session.fetchOne(d) }
        XCTAssertEqual(fetched?.privateKeyPath, "/Users/test/.ssh/id_ed25519")
    }
}
