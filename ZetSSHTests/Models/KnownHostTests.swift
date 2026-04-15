import XCTest
import GRDB
@testable import zetssh

final class KnownHostTests: XCTestCase {

    var db: DatabaseWriter!

    override func setUp() async throws {
        db = try makeTestDatabase()
    }

    func testSaveAndFetchKnownHost() throws {
        let kh = KnownHost(host: "server.com", port: 22,
                           algorithm: "ssh-ed25519",
                           fingerprint: "aabbcc",
                           addedAt: Date())
        try db.write { d in try kh.save(d) }
        let fetched = try db.read { d in
            try KnownHost
                .filter(Column("host") == "server.com")
                .filter(Column("port") == 22)
                .filter(Column("algorithm") == "ssh-ed25519")
                .fetchOne(d)
        }
        XCTAssertEqual(fetched?.fingerprint, "aabbcc")
    }

    func testDifferentAlgorithmsDifferentRows() throws {
        let kh1 = KnownHost(host: "s.com", port: 22, algorithm: "ssh-ed25519",
                            fingerprint: "fp1", addedAt: Date())
        let kh2 = KnownHost(host: "s.com", port: 22, algorithm: "rsa-sha2-256",
                            fingerprint: "fp2", addedAt: Date())
        try db.write { d in try kh1.save(d); try kh2.save(d) }
        let count = try db.read { d in try KnownHost.fetchCount(d) }
        XCTAssertEqual(count, 2)
    }
}
