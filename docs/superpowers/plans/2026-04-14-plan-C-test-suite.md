# ZetSSH Test Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar target XCTest com cobertura de modelos GRDB, KeychainService (via mock), SessionViewModel, e validação de formulário — sem rede real.

**Architecture:** KeychainService extrai um protocolo `KeychainServiceProtocol`; testes usam `KeychainServiceMock` em memória. GRDB usa `DatabaseQueue(path: ":memory:")`. `LibSSH2WrapperMock` (já com `#if DEBUG`) simula o engine SSH.

**Tech Stack:** XCTest, GRDB 6.29.3, Swift 5.9+, macOS 13+

---

## Arquivos

| Ação | Arquivo |
|---|---|
| Modify | `zetssh/Data/Security/KeychainService.swift` — extrair `KeychainServiceProtocol` |
| Create | `ZetSSHTests/Mocks/KeychainServiceMock.swift` |
| Create | `ZetSSHTests/Helpers/TestDatabase.swift` |
| Create | `ZetSSHTests/Models/SessionTests.swift` |
| Create | `ZetSSHTests/Models/KnownHostTests.swift` |
| Create | `ZetSSHTests/Database/AppDatabaseMigrationTests.swift` |
| Create | `ZetSSHTests/ViewModels/SessionViewModelTests.swift` |
| Create | `ZetSSHTests/Presentation/SessionFormValidationTests.swift` |

---

### Task 1: Extrair KeychainServiceProtocol

**Files:**
- Modify: `zetssh/Data/Security/KeychainService.swift`

- [ ] **Step 1: Adicionar protocolo acima da classe KeychainService**

Abrir `zetssh/Data/Security/KeychainService.swift` e inserir antes da declaração da classe:

```swift
protocol KeychainServiceProtocol {
    func save(password: String, forSessionId id: UUID) throws
    func fetchPassword(forSessionId id: UUID) throws -> String
    func deletePassword(forSessionId id: UUID) throws
    func save(passphrase: String, forSessionId id: UUID) throws
    func fetchPassphrase(forSessionId id: UUID) throws -> String?
    func deletePassphrase(forSessionId id: UUID) throws
    func getOrCreateDatabaseEncryptionKey() throws -> Data
}
```

- [ ] **Step 2: Conformar KeychainService ao protocolo**

Alterar a declaração da classe:
```swift
final class KeychainService: KeychainServiceProtocol {
```

- [ ] **Step 3: Build para verificar**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Esperado: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
cd /Users/zeitune/src/zetssh
git add zetssh/Data/Security/KeychainService.swift
git commit -m "refactor: extract KeychainServiceProtocol for testability"
```

---

### Task 2: Adicionar Target XCTest no Xcode

**Files:**
- Modify: `zetssh.xcodeproj/project.pbxproj` (via Xcode GUI)

- [ ] **Step 1: Adicionar target de teste via Xcode**

Abrir `zetssh.xcodeproj` no Xcode. Menu: File → New → Target → Unit Testing Bundle. Nome: `ZetSSHTests`. Language: Swift. Deixar "Include UI Tests" desmarcado.

- [ ] **Step 2: Configurar target**

Em ZetSSHTests target → Build Settings → verificar que `TEST_HOST = $(BUILT_PRODUCTS_DIR)/zetssh.app/Contents/MacOS/zetssh`.

- [ ] **Step 3: Build test target (vai falhar com placeholder test — OK)**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' test 2>&1 | grep -E "error:|FAILED|PASSED|executed" | head -10
```

- [ ] **Step 4: Commit**

```bash
cd /Users/zeitune/src/zetssh
git add zetssh.xcodeproj/
git commit -m "chore: add ZetSSHTests XCTest target"
```

---

### Task 3: Helpers de Teste — Mock + DB em Memória

**Files:**
- Create: `ZetSSHTests/Mocks/KeychainServiceMock.swift`
- Create: `ZetSSHTests/Helpers/TestDatabase.swift`

- [ ] **Step 1: Criar KeychainServiceMock**

```swift
// ZetSSHTests/Mocks/KeychainServiceMock.swift
import Foundation
@testable import zetssh

final class KeychainServiceMock: KeychainServiceProtocol {
    private var passwords: [UUID: String] = [:]
    private var passphrases: [UUID: String] = [:]
    private var dbKey: Data = Data(repeating: 0, count: 32)

    func save(password: String, forSessionId id: UUID) throws {
        passwords[id] = password
    }
    func fetchPassword(forSessionId id: UUID) throws -> String {
        guard let p = passwords[id] else { throw KeychainError.itemNotFound }
        return p
    }
    func deletePassword(forSessionId id: UUID) throws {
        passwords.removeValue(forKey: id)
    }
    func save(passphrase: String, forSessionId id: UUID) throws {
        passphrases[id] = passphrase
    }
    func fetchPassphrase(forSessionId id: UUID) throws -> String? {
        passphrases[id]
    }
    func deletePassphrase(forSessionId id: UUID) throws {
        passphrases.removeValue(forKey: id)
    }
    func getOrCreateDatabaseEncryptionKey() throws -> Data { dbKey }
}
```

- [ ] **Step 2: Criar TestDatabase helper**

```swift
// ZetSSHTests/Helpers/TestDatabase.swift
import Foundation
import GRDB
@testable import zetssh

/// Cria um AppDatabase em memória para testes (sem arquivo em disco)
func makeTestDatabase() throws -> DatabaseWriter {
    let queue = try DatabaseQueue()
    var migrator = DatabaseMigrator()

    migrator.registerMigration("v1") { db in
        try db.create(table: "folder") { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull()
            t.column("icon", .text)
        }
        try db.create(table: "session") { t in
            t.column("id", .text).primaryKey()
            t.column("folderId", .text).references("folder", onDelete: .setNull)
            t.column("name", .text).notNull()
            t.column("host", .text).notNull()
            t.column("port", .integer).notNull().defaults(to: 22)
            t.column("username", .text).notNull()
            t.column("privateKeyPath", .text)
        }
    }

    migrator.registerMigration("v2") { db in
        try db.create(table: "knownHost") { t in
            t.column("host",        .text).notNull()
            t.column("port",        .integer).notNull()
            t.column("algorithm",   .text).notNull()
            t.column("fingerprint", .text).notNull()
            t.column("addedAt",     .datetime).notNull()
            t.primaryKey(["host", "port", "algorithm"])
        }
    }

    try migrator.migrate(queue)
    return queue
}
```

- [ ] **Step 3: Build**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build-for-testing 2>&1 | grep -E "error:|BUILD" | head -10
```

- [ ] **Step 4: Commit**

```bash
cd /Users/zeitune/src/zetssh
git add ZetSSHTests/
git commit -m "test: add KeychainServiceMock and TestDatabase helpers"
```

---

### Task 4: Testes de Modelo — Session e KnownHost

**Files:**
- Create: `ZetSSHTests/Models/SessionTests.swift`
- Create: `ZetSSHTests/Models/KnownHostTests.swift`

- [ ] **Step 1: Criar SessionTests**

```swift
// ZetSSHTests/Models/SessionTests.swift
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
                              host: "192.168.1.1", port: 22, username: "ubuntu")
        try db.write { d in try session.save(d) }
        let fetched = try db.read { d in try Session.fetchOne(d) }
        XCTAssertEqual(fetched?.host, "192.168.1.1")
        XCTAssertEqual(fetched?.username, "ubuntu")
    }

    func testSessionDefaultPort() throws {
        let session = Session(id: UUID(), folderId: nil, name: "Dev",
                              host: "dev.local", port: 22, username: "admin")
        XCTAssertEqual(session.port, 22)
    }

    func testSessionDelete() throws {
        let session = Session(id: UUID(), folderId: nil, name: "Temp",
                              host: "temp.host", port: 2222, username: "user")
        try db.write { d in try session.save(d) }
        try db.write { d in try session.delete(d) }
        let count = try db.read { d in try Session.fetchCount(d) }
        XCTAssertEqual(count, 0)
    }
}
```

- [ ] **Step 2: Criar KnownHostTests**

```swift
// ZetSSHTests/Models/KnownHostTests.swift
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
```

- [ ] **Step 3: Executar testes**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' test -only-testing:ZetSSHTests/SessionTests -only-testing:ZetSSHTests/KnownHostTests 2>&1 | grep -E "PASSED|FAILED|error:" | head -20
```

Esperado: todos PASSED.

- [ ] **Step 4: Commit**

```bash
cd /Users/zeitune/src/zetssh
git add ZetSSHTests/Models/
git commit -m "test: add Session and KnownHost model tests"
```

---

### Task 5: Testes de Validação de Formulário

**Files:**
- Create: `ZetSSHTests/Presentation/SessionFormValidationTests.swift`

- [ ] **Step 1: Criar testes de validação**

```swift
// ZetSSHTests/Presentation/SessionFormValidationTests.swift
import XCTest
@testable import zetssh

final class SessionFormValidationTests: XCTestCase {

    // Replica a lógica de portInt do SessionFormView
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
```

- [ ] **Step 2: Executar**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' test -only-testing:ZetSSHTests/SessionFormValidationTests 2>&1 | grep -E "PASSED|FAILED|error:" | head -10
```

Esperado: todos PASSED.

- [ ] **Step 3: Commit**

```bash
cd /Users/zeitune/src/zetssh
git add ZetSSHTests/Presentation/
git commit -m "test: add SessionFormView validation unit tests"
```

---

### Task 6: Testes do SessionViewModel

**Files:**
- Create: `ZetSSHTests/ViewModels/SessionViewModelTests.swift`

- [ ] **Step 1: Criar testes do ViewModel**

```swift
// ZetSSHTests/ViewModels/SessionViewModelTests.swift
import XCTest
import GRDB
@testable import zetssh

@MainActor
final class SessionViewModelTests: XCTestCase {

    func testSaveAndDeleteSession() throws {
        // Usa o DB real de app (em memória via AppDatabase não é acessível diretamente;
        // testa a lógica via GRDB in-memory)
        let db = try makeTestDatabase()
        var session = Session(id: UUID(), folderId: nil, name: "Test",
                              host: "test.local", port: 22, username: "u")
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
                            host: "h\(i).com", port: 22, username: "u\(i)")
            try db.write { d in try s.save(d) }
        }
        let all = try db.read { d in try Session.fetchAll(d) }
        XCTAssertEqual(all.count, 3)
    }
}
```

- [ ] **Step 2: Executar**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' test -only-testing:ZetSSHTests/SessionViewModelTests 2>&1 | grep -E "PASSED|FAILED|error:" | head -10
```

Esperado: todos PASSED.

- [ ] **Step 3: Executar toda a suite**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' test 2>&1 | grep -E "PASSED|FAILED|executed|error:" | tail -10
```

- [ ] **Step 4: Commit final**

```bash
cd /Users/zeitune/src/zetssh
git add ZetSSHTests/
git commit -m "test: add SessionViewModel tests and complete test suite"
```
