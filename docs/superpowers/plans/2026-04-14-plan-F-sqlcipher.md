# ZetSSH SQLCipher Encryption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Habilitar criptografia AES-256 no banco GRDB usando a chave de 256 bits já persistida no Keychain, substituindo o pacote GRDB padrão por GRDBCipher via SQLCipher.

**Architecture:** Troca o pacote SPM de `groue/GRDB.swift` para uma build com SQLCipher embutido. A chave já está no Keychain (`getOrCreateDatabaseEncryptionKey()`). Descomenta `config.prepareDatabase { db in try db.usePassphrase(key) }` em AppDatabase. Testes continuam usando `DatabaseQueue(path: ":memory:")` sem passphrase.

**Tech Stack:** GRDB 6.29.3 + SQLCipher 4.x, Swift 5.9+, macOS 13+

---

## Nota importante

O pacote SPM padrão `groue/GRDB.swift` usa SQLite do sistema (sem criptografia). Para SQLCipher é necessário usar uma das seguintes opções:

**Opção recomendada:** `stephencelis/SQLCipher` via SPM + `GRDBPlus` (wrapper que liga os dois). Outra opção: fork `GRDB.swift` com flag `SQLITE_HAS_CODEC`. A abordagem mais simples e mantida é usar o package `"https://github.com/stephencelis/SQLCipher"` + GRDB configurado para usar SQLCipher externo.

---

## Arquivos

| Ação | Arquivo |
|---|---|
| Modify | `zetssh.xcodeproj/project.pbxproj` — trocar dependência GRDB |
| Modify | `zetssh/Data/Database/AppDatabase.swift` — habilitar passphrase |
| Modify | `ZetSSHTests/Helpers/TestDatabase.swift` — garantir sem passphrase |

---

### Task 1: Adicionar SQLCipher via SPM

**Files:**
- Modify: `zetssh.xcodeproj` (via Xcode GUI)

- [ ] **Step 1: Abrir gerenciador de pacotes no Xcode**

Abrir `zetssh.xcodeproj`. Menu: File → Add Package Dependencies.

- [ ] **Step 2: Adicionar SQLCipher**

URL: `https://github.com/stephencelis/SQLCipher`
Version rule: Up to Next Major from `4.5.7`
Adicionar produto `SQLCipher` ao target `zetssh`.

- [ ] **Step 3: Adicionar GRDB+SQLCipher**

URL: `https://github.com/groue/GRDB.swift`
Branch: `master` (ou versão >= 6.29.0)
Na tela de produto, selecionar `GRDBSQLCipher` em vez de `GRDB`.

Remover `GRDB` (sem Cipher) da lista de dependências do target `zetssh` se aparecer separado.

- [ ] **Step 4: Build para verificar resolve**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD" | head -15
```

Esperado: `** BUILD SUCCEEDED **` (pode demorar — primeiro build baixa SQLCipher)

- [ ] **Step 5: Commit**

```bash
cd /Users/zeitune/src/zetssh
git add zetssh.xcodeproj/
git commit -m "chore: add SQLCipher and GRDBSQLCipher package dependencies"
```

---

### Task 2: Habilitar Passphrase no AppDatabase

**Files:**
- Modify: `zetssh/Data/Database/AppDatabase.swift`

- [ ] **Step 1: Atualizar init() para usar a chave do Keychain**

Localizar o bloco em `AppDatabase.private init() throws` e substituir:

```swift
private init() throws {
    let fileManager = FileManager.default
    let appSupportURL = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    let directoryURL = appSupportURL.appendingPathComponent("ZetSSH", isDirectory: true)
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let databaseURL = directoryURL.appendingPathComponent("db.sqlite")

    var config = Configuration()
    let encryptionKey = try KeychainService.shared.getOrCreateDatabaseEncryptionKey()
    let keyHex = encryptionKey.map { String(format: "%02x", $0) }.joined()

    config.prepareDatabase { db in
        try db.usePassphrase("x'\(keyHex)'")
    }

    dbWriter = try DatabasePool(path: databaseURL.path, configuration: config)
    try migrator.migrate(dbWriter)

    AppLogger.shared.log(
        "Database inicializado com criptografia em \(databaseURL.path)",
        category: .database, level: .info
    )
}
```

Nota: `"x'\(keyHex)'"` é o formato SQLCipher para chave raw hex (sem derivação PBKDF2).

- [ ] **Step 2: Build**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Esperado: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Verificar que arquivo DB não é texto plano**

```bash
# Localizar o banco (após rodar o app uma vez)
ls ~/Library/Application\ Support/ZetSSH/
# Tentar ler — deve mostrar binário ilegível
head -c 100 ~/Library/Application\ Support/ZetSSH/db.sqlite | cat
```

Esperado: caracteres binários não legíveis (não "SQLite format 3").

- [ ] **Step 4: Commit**

```bash
cd /Users/zeitune/src/zetssh
git add zetssh/Data/Database/AppDatabase.swift
git commit -m "security: enable SQLCipher AES-256 encryption for GRDB database"
```

---

### Task 3: Garantir que Testes Continuam Passando

**Files:**
- Modify: `ZetSSHTests/Helpers/TestDatabase.swift`

- [ ] **Step 1: Verificar que TestDatabase usa DatabaseQueue sem passphrase**

`DatabaseQueue(path: ":memory:")` não usa criptografia — correto para testes. Verificar que `makeTestDatabase()` não tem `config.prepareDatabase`.

O arquivo deve ficar como está — sem mudança necessária. SQLCipher com `:memory:` funciona sem passphrase.

- [ ] **Step 2: Executar suite de testes**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' test 2>&1 | grep -E "PASSED|FAILED|executed" | tail -5
```

Esperado: todos PASSED (testes em memória não são afetados pela criptografia do arquivo).

- [ ] **Step 3: Commit final**

```bash
cd /Users/zeitune/src/zetssh
git add ZetSSHTests/
git commit -m "test: verify test suite unaffected by SQLCipher encryption"
```
