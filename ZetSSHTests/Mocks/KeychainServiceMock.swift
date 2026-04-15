import Foundation
@testable import zetssh

final class KeychainServiceMock: KeychainServiceProtocol {
    private var passwords: [UUID: String] = [:]
    private var passphrases: [UUID: String] = [:]
    private var dbKey: String = "mock-db-key-64chars-padded-to-fit-protocol-requirement-here00"

    func save(password: String, forSessionId id: UUID) throws {
        passwords[id] = password
    }
    func fetchPassword(forSessionId id: UUID) throws -> String? {
        passwords[id]
    }
    func deletePassword(forSessionId id: UUID) throws {
        passwords.removeValue(forKey: id)
    }
    func savePassphrase(_ passphrase: String, forSessionId sessionId: UUID) throws {
        passphrases[sessionId] = passphrase
    }
    func fetchPassphrase(forSessionId sessionId: UUID) throws -> String? {
        passphrases[sessionId]
    }
    func deletePassphrase(forSessionId sessionId: UUID) throws {
        passphrases.removeValue(forKey: sessionId)
    }
    func getOrCreateDatabaseEncryptionKey() throws -> String { dbKey }
}
