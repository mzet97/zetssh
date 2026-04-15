import XCTest
@testable import zetssh

final class SessionFormValidationTests: XCTestCase {

    private func portInt(from string: String) -> Int? {
        guard let p = Int(string.trimmingCharacters(in: .whitespaces)),
              (1...65535).contains(p) else { return nil }
        return p
    }

    func testValidPort() {
        XCTAssertEqual(portInt(from: "22"), 22)
        XCTAssertEqual(portInt(from: "2222"), 2222)
        XCTAssertEqual(portInt(from: "65535"), 65535)
        XCTAssertEqual(portInt(from: "1"), 1)
    }

    func testInvalidPort() {
        XCTAssertNil(portInt(from: "0"))
        XCTAssertNil(portInt(from: "65536"))
        XCTAssertNil(portInt(from: "abc"))
        XCTAssertNil(portInt(from: ""))
        XCTAssertNil(portInt(from: "-1"))
    }

    func testPortWithWhitespace() {
        XCTAssertEqual(portInt(from: " 22 "), 22)
    }

    func testHostTrim() {
        let host = "  server.com  "
        XCTAssertEqual(host.trimmingCharacters(in: .whitespacesAndNewlines), "server.com")
    }
}
