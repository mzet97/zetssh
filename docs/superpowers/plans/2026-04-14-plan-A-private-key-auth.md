# Private Key Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add SSH private key authentication to ZetSSH so users can connect to servers using PEM/OpenSSH keys with optional passphrase, as an alternative to password auth.
**Architecture:** The feature is split into four layers — Domain (Session model + GRDB migration), Data/Security (Keychain passphrase methods), Data/Network (NIOSSH private key delegate + engine method), and Presentation (SessionFormView segmented picker + TerminalView routing). Each layer is independently testable and committed separately.
**Tech Stack:** Swift 5.10, SwiftUI, GRDB 6, Security.framework (Keychain), SwiftNIO-SSH (NIOSSH), SwiftTerm, AppKit (NSOpenPanel)

---

## Prerequisites — read before starting

- All edits are inside `/Users/zeitune/src/zetssh/zetssh/` (the Swift source root).
- The Xcode project is at `/Users/zeitune/src/zetssh/zetssh.xcodeproj`.
- Build verification command (run after every task):
  ```bash
  xcodebuild -project /Users/zeitune/src/zetssh/zetssh.xcodeproj \
    -scheme zetssh \
    -destination 'platform=macOS' \
    build 2>&1 | grep -E "error:|BUILD"
  ```
- The migrator in `AppDatabase.swift` is `private var migrator: DatabaseMigrator`. Add `v3` by appending a new `registerMigration` call inside that computed var, before the `return migrator` statement.
- NIOSSH private key type: `NIOSSHPrivateKey`. Constructor signatures:
  - No passphrase: `NIOSSHPrivateKey(pemRepresentation: String)`
  - With passphrase: `NIOSSHPrivateKey(pemRepresentation: String, passphrase: [UInt8])`
  Both constructors throw.

---

## Task 1 — Domain: add `privateKeyPath` to Session and migrate the database

**Files changed:**
- `Domain/Models/Session.swift`
- `Data/Database/AppDatabase.swift`

### Steps

- [ ] **1.1** Open `Domain/Models/Session.swift`. Replace the entire file with:

```swift
import Foundation
import GRDB

struct Session: Identifiable, Hashable, Codable, FetchableRecord, PersistableRecord {
    var id: UUID
    var folderId: UUID?
    var name: String
    var host: String
    var port: Int
    var username: String
    /// Absolute path to the private key file on disk. `nil` means password auth.
    var privateKeyPath: String?
}
```

- [ ] **1.2** Open `Data/Database/AppDatabase.swift`. Inside `private var migrator: DatabaseMigrator`, add the v3 migration block **after** the closing brace of `registerMigration("v2")` and **before** `return migrator`:

```swift
        migrator.registerMigration("v3") { db in
            try db.alter(table: "session") { t in
                t.add(column: "privateKeyPath", .text)
            }
        }
```

The resulting migrator block (showing context) will be:

```swift
    private var migrator: DatabaseMigrator {
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

        migrator.registerMigration("v3") { db in
            try db.alter(table: "session") { t in
                t.add(column: "privateKeyPath", .text)
            }
        }

        return migrator
    }
```

- [ ] **1.3** Build and confirm no errors:
  ```bash
  xcodebuild -project /Users/zeitune/src/zetssh/zetssh.xcodeproj \
    -scheme zetssh \
    -destination 'platform=macOS' \
    build 2>&1 | grep -E "error:|BUILD"
  ```

- [ ] **1.4** Commit:
  ```bash
  cd /Users/zeitune/src/zetssh && git add zetssh/Domain/Models/Session.swift zetssh/Data/Database/AppDatabase.swift && git commit -m "feat(domain): add privateKeyPath to Session + GRDB migration v3"
  ```

---

## Task 2 — Security: add passphrase Keychain methods

**Files changed:**
- `Data/Security/KeychainService.swift`

### Steps

- [ ] **2.1** Open `Data/Security/KeychainService.swift`. The passphrase is stored under a separate Keychain account key so it never collides with the password entry. Add the three passphrase methods at the end of the class body, before the final closing brace:

```swift
    // MARK: - Passphrase (private key)

    /// Stores the passphrase for a private key associated with `sessionId`.
    /// The account key is distinct from the password key (`"\(id)-passphrase"`).
    func savePassphrase(_ passphrase: String, forSessionId sessionId: UUID) throws {
        guard let data = passphrase.data(using: .utf8) else { return }
        let account = "\(sessionId.uuidString)-passphrase"

        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      serviceName,
            kSecAttrAccount as String:      account,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }
    }

    /// Returns the stored passphrase, or `nil` if none was saved (key has no passphrase).
    func fetchPassphrase(forSessionId sessionId: UUID) throws -> String? {
        let account = "\(sessionId.uuidString)-passphrase"

        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      serviceName,
            kSecAttrAccount as String:      account,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecItemNotFound { return nil }

        guard status == errSecSuccess,
              let data = dataTypeRef as? Data,
              let passphrase = String(data: data, encoding: .utf8) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }
        return passphrase
    }

    /// Removes the stored passphrase. Safe to call even if none exists.
    func deletePassphrase(forSessionId sessionId: UUID) throws {
        let account = "\(sessionId.uuidString)-passphrase"

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }
    }
```

- [ ] **2.2** Build and confirm no errors.

- [ ] **2.3** Commit:
  ```bash
  cd /Users/zeitune/src/zetssh && git add zetssh/Data/Security/KeychainService.swift && git commit -m "feat(security): add passphrase Keychain methods for private key auth"
  ```

---

## Task 3 — Network: implement PrivateKeyAuthenticationDelegate and wire authenticate(privateKeyPath:passphrase:)

**Files changed:**
- `Data/Network/RealSSHEngine.swift`

### Steps

- [ ] **3.1** Open `Data/Network/RealSSHEngine.swift`. Replace the current stub implementation of `authenticate(privateKeyPath:passphrase:)` (lines 71–80) with the full implementation:

```swift
    public func authenticate(privateKeyPath: URL, passphrase: String?) async throws {
        guard connectionState == .idle else {
            throw SSHConnectionError.alreadyConnecting
        }
        connectionState = .connecting

        // Read PEM file from disk.
        let pemString: String
        do {
            pemString = try String(contentsOf: privateKeyPath, encoding: .utf8)
        } catch {
            connectionState = .idle
            AppLogger.shared.log(
                "Falha ao ler chave privada em \(privateKeyPath.path): \(error)",
                category: .security, level: .error
            )
            throw SSHConnectionError.authenticationFailed
        }

        // Parse the private key, with or without passphrase.
        let privateKey: NIOSSHPrivateKey
        do {
            if let passphrase, !passphrase.isEmpty {
                privateKey = try NIOSSHPrivateKey(
                    pemRepresentation: pemString,
                    passphrase: Array(passphrase.utf8)
                )
            } else {
                privateKey = try NIOSSHPrivateKey(pemRepresentation: pemString)
            }
        } catch {
            connectionState = .idle
            AppLogger.shared.log(
                "Falha ao parsear chave privada: \(error)",
                category: .security, level: .error
            )
            throw SSHConnectionError.authenticationFailed
        }

        let authDelegate = PrivateKeyAuthenticationDelegate(
            username: pendingUsername,
            privateKey: privateKey
        )

        do {
            try await establishConnection(authDelegate: authDelegate)
            connectionState = .connected
        } catch {
            connectionState = .idle
            throw error
        }
    }
```

- [ ] **3.2** Add `PrivateKeyAuthenticationDelegate` to the `// MARK: - Private Delegates` section at the bottom of `RealSSHEngine.swift`, after `PasswordAuthenticationDelegate`:

```swift
private final class PrivateKeyAuthenticationDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let privateKey: NIOSSHPrivateKey

    init(username: String, privateKey: NIOSSHPrivateKey) {
        self.username = username
        self.privateKey = privateKey
    }

    nonisolated func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        if availableMethods.contains(.publicKey) {
            nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(
                username: username,
                serviceName: "",
                offer: .privateKey(.init(privateKey: privateKey))
            ))
        } else {
            // Server does not advertise publicKey — signal end of attempts.
            nextChallengePromise.succeed(nil)
        }
    }
}
```

- [ ] **3.3** Build and confirm no errors.

- [ ] **3.4** Commit:
  ```bash
  cd /Users/zeitune/src/zetssh && git add zetssh/Data/Network/RealSSHEngine.swift && git commit -m "feat(network): implement private key auth delegate and engine method"
  ```

---

## Task 4 — Presentation: update SessionFormView with auth-mode picker and key selector

**Files changed:**
- `Presentation/Sessions/SessionFormView.swift`

### Design (A1)

A `Picker` rendered as `.segmented` switches between `"Senha"` and `"Chave Privada"`. When `"Senha"` is selected the existing `SecureField` is shown. When `"Chave Privada"` is selected, a read-only text field shows the chosen key path plus a `"Escolher…"` button that opens `NSOpenPanel`, and a `SecureField` for the optional passphrase.

### Callback signature change

`onSave` currently is `(Session, String) -> Void` where the `String` is always the password. After this task it becomes `(Session, SessionCredentials) -> Void` where `SessionCredentials` is a new enum defined at the top of `SessionFormView.swift`.

> **Important:** The call sites of `onSave` (inside `SessionsView` or wherever `SessionFormView` is initialised) must be updated in this same task so the project compiles. Find those call sites with:
> ```bash
> grep -rn "SessionFormView" /Users/zeitune/src/zetssh/zetssh/
> ```

### Steps

- [ ] **4.1** Replace `Presentation/Sessions/SessionFormView.swift` entirely with the following:

```swift
import SwiftUI
import AppKit

// MARK: - Credential payload

enum SessionCredentials {
    case password(String)
    case privateKey(path: String, passphrase: String?)
}

// MARK: - Auth mode

private enum AuthMode: String, CaseIterable, Identifiable {
    case password    = "Senha"
    case privateKey  = "Chave Privada"
    var id: String { rawValue }
}

// MARK: - SessionFormView

struct SessionFormView: View {
    @Environment(\.dismiss) var dismiss

    @State private var name:        String   = ""
    @State private var host:        String   = ""
    @State private var port:        String   = "22"
    @State private var username:    String   = ""
    @State private var portError:   String?  = nil
    @State private var authMode:    AuthMode = .password

    // Password branch
    @State private var password:    String = ""

    // Private key branch
    @State private var keyPath:     String = ""
    @State private var passphrase:  String = ""

    var onSave: (Session, SessionCredentials) -> Void

    private var trimmedHost:     String { host.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedUsername: String { username.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var portInt: Int? {
        guard let p = Int(port.trimmingCharacters(in: .whitespaces)),
              (1...65535).contains(p) else { return nil }
        return p
    }
    private var isFormValid: Bool {
        guard !trimmedHost.isEmpty, !trimmedUsername.isEmpty, portInt != nil else { return false }
        if authMode == .privateKey { return !keyPath.isEmpty }
        return true
    }

    var body: some View {
        Form {
            Section(header: Text("Geral").font(.headline)) {
                TextField("Nome (ex: Prod Server)", text: $name)
                TextField("Host / IP (obrigatório)", text: $host)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Porta", text: $port)
                        .onChange(of: port) { _ in validatePort() }
                    if let err = portError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }
            }

            Section(header: Text("Credenciais").font(.headline)) {
                TextField("Usuário (obrigatório)", text: $username)

                Picker("Autenticação", selection: $authMode) {
                    ForEach(AuthMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if authMode == .password {
                    SecureField("Senha", text: $password)
                        .help("Armazenada com segurança no Keychain do macOS")
                } else {
                    keyPickerRow
                    SecureField("Frase-senha (opcional)", text: $passphrase)
                        .help("Deixe em branco se a chave não tem frase-senha")
                }
            }

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Salvar") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isFormValid)
            }
            .padding(.top)
        }
        .padding(24)
        .frame(minWidth: 460, minHeight: 340)
    }

    // MARK: - Private key picker row

    private var keyPickerRow: some View {
        HStack {
            Text(keyPath.isEmpty ? "Nenhuma chave selecionada" : keyPath)
                .foregroundStyle(keyPath.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Escolher…") { pickKeyFile() }
        }
    }

    // MARK: - Helpers

    private func validatePort() {
        let trimmed = port.trimmingCharacters(in: .whitespaces)
        if let p = Int(trimmed) {
            portError = (1...65535).contains(p) ? nil : "Porta deve estar entre 1 e 65535"
        } else {
            portError = trimmed.isEmpty ? nil : "Porta inválida"
        }
    }

    private func pickKeyFile() {
        let panel = NSOpenPanel()
        panel.title = "Selecionar chave privada SSH"
        panel.message = "Escolha um arquivo de chave privada (PEM ou OpenSSH)"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        // Start in ~/.ssh if it exists
        if let sshDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true) as URL?,
           FileManager.default.fileExists(atPath: sshDir.path) {
            panel.directoryURL = sshDir
        }
        if panel.runModal() == .OK, let url = panel.url {
            keyPath = url.path
        }
    }

    private func save() {
        guard let portValue = portInt else { return }
        let sessionName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newSession = Session(
            id:             UUID(),
            folderId:       nil,
            name:           sessionName.isEmpty ? trimmedHost : sessionName,
            host:           trimmedHost,
            port:           portValue,
            username:       trimmedUsername,
            privateKeyPath: authMode == .privateKey ? keyPath : nil
        )

        let credentials: SessionCredentials
        switch authMode {
        case .password:
            credentials = .password(password)
        case .privateKey:
            credentials = .privateKey(
                path: keyPath,
                passphrase: passphrase.isEmpty ? nil : passphrase
            )
        }

        onSave(newSession, credentials)
        dismiss()
    }
}
```

- [ ] **4.2** Find and update every call site of `SessionFormView(onSave:)`. Run:
  ```bash
  grep -rn "onSave" /Users/zeitune/src/zetssh/zetssh/Presentation/Sessions/
  ```
  For each call site that pattern-matches `onSave: { session, password in … }`, update the closure signature to `onSave: { session, credentials in … }` and store credentials appropriately. The canonical pattern for a call site inside a `SessionsViewModel` or similar that previously called `KeychainService.shared.save(password:forSessionId:)` is:

  ```swift
  SessionFormView { session, credentials in
      do {
          try AppDatabase.shared.dbWriter.write { db in try session.save(db) }
          switch credentials {
          case .password(let pw):
              try KeychainService.shared.save(password: pw, forSessionId: session.id)
              try KeychainService.shared.deletePassphrase(forSessionId: session.id)
          case .privateKey(let path, let passphrase):
              try KeychainService.shared.deletePassword(forSessionId: session.id)
              if let passphrase {
                  try KeychainService.shared.savePassphrase(passphrase, forSessionId: session.id)
              } else {
                  try KeychainService.shared.deletePassphrase(forSessionId: session.id)
              }
          }
      } catch {
          AppLogger.shared.log("Erro ao salvar sessão: \(error)", category: .database, level: .error)
      }
  }
  ```

  Adapt field names to match the actual call site structure you find.

- [ ] **4.3** Build and confirm no errors.

- [ ] **4.4** Commit:
  ```bash
  cd /Users/zeitune/src/zetssh && git add zetssh/Presentation/Sessions/SessionFormView.swift && git commit -m "feat(ui): add auth-mode segmented picker and NSOpenPanel key selector to SessionFormView"
  ```

---

## Task 5 — Presentation: update TerminalView Coordinator to route to the correct auth method

**Files changed:**
- `Presentation/Terminal/TerminalView.swift`

### Steps

- [ ] **5.1** Replace `Presentation/Terminal/TerminalView.swift` entirely with the following. The key change is that `SSHTerminalView` now accepts `privateKeyPath: String?`, the Coordinator gains `privateKeyPath` and `passphrase` properties, and `connect()` dispatches to the appropriate `engine.authenticate` overload:

```swift
import SwiftUI
import SwiftTerm
import NIOCore

// MARK: - SSHTerminalView

/// NSViewRepresentable integrating SwiftTerm (VT100/xterm emulation)
/// with RealSSHEngine (SwiftNIO-SSH) for a 100% in-process SSH session.
struct SSHTerminalView: NSViewRepresentable {
    let host:           String
    let port:           Int
    let username:       String
    let sessionId:      UUID
    /// Absolute path to the private key file, or `nil` when using password auth.
    let privateKeyPath: String?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SwiftTerm.TerminalView {
        let termView = SwiftTerm.TerminalView(frame: .zero)
        termView.terminalDelegate = context.coordinator
        context.coordinator.terminalView = termView

        let engine = RealSSHEngine()
        engine.delegate = context.coordinator
        context.coordinator.engine         = engine
        context.coordinator.host           = host
        context.coordinator.port           = port
        context.coordinator.username       = username
        context.coordinator.privateKeyPath = privateKeyPath

        if let keyPath = privateKeyPath {
            // Private key auth: load passphrase from Keychain (may be nil).
            context.coordinator.passphrase =
                try? KeychainService.shared.fetchPassphrase(forSessionId: sessionId)
            AppLogger.shared.log(
                "Auth mode: private key at \(keyPath)",
                category: .security, level: .info
            )
        } else {
            // Password auth.
            context.coordinator.password =
                (try? KeychainService.shared.fetchPassword(forSessionId: sessionId)) ?? ""
        }

        return termView
    }

    func updateNSView(_ nsView: SwiftTerm.TerminalView, context: Context) {
        guard !context.coordinator.didConnect else { return }
        context.coordinator.didConnect = true
        context.coordinator.connect()
    }

    static func dismantleNSView(_ nsView: SwiftTerm.TerminalView, coordinator: Coordinator) {
        coordinator.engine?.disconnect()
        coordinator.engine = nil
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var engine:         (any SSHEngine)?
        var host:           String  = ""
        var port:           Int     = 22
        var username:       String  = ""
        var password:       String  = ""
        var privateKeyPath: String? = nil
        var passphrase:     String? = nil
        var didConnect:     Bool    = false
        weak var terminalView: SwiftTerm.TerminalView?

        func connect() {
            guard let engine, let termView = terminalView else { return }
            termView.feed(text: "Connecting to \(username)@\(host):\(port)...\r\n")

            Task { @MainActor in
                do {
                    try await engine.connect(host: host, port: port, username: username)

                    if let keyPathString = privateKeyPath {
                        let keyURL = URL(fileURLWithPath: keyPathString)
                        termView.feed(text: "Using private key: \(keyPathString)\r\n")
                        try await engine.authenticate(privateKeyPath: keyURL, passphrase: passphrase)
                    } else {
                        try await engine.authenticate(password: password)
                    }
                } catch {
                    termView.feed(
                        text: "\r\n\u{1B}[31mConnection failed: \(error.localizedDescription)\u{1B}[0m\r\n"
                    )
                }
            }
        }
    }
}

// MARK: - SSHClientDelegate

extension SSHTerminalView.Coordinator: SSHClientDelegate {
    func onDataReceived(_ data: ByteBuffer) {
        var buf = data
        guard let bytes = buf.readBytes(length: buf.readableBytes), !bytes.isEmpty else { return }
        terminalView?.feed(byteArray: bytes[...])
    }

    func onError(_ error: Error) {
        terminalView?.feed(
            text: "\r\n\u{1B}[31mSSH Error: \(error.localizedDescription)\u{1B}[0m\r\n"
        )
    }

    func onDisconnected() {
        terminalView?.feed(
            text: "\r\n\u{1B}[33m[Connection closed. Select a session to reconnect.]\u{1B}[0m\r\n"
        )
    }
}

// MARK: - TerminalViewDelegate

extension SSHTerminalView.Coordinator: TerminalViewDelegate {
    func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
        engine?.sendData(Array(data))
    }

    func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
        engine?.resize(cols: newCols, rows: newRows)
    }

    func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
    func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
    func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {}
    func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {}
    func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
}
```

- [ ] **5.2** Find every `SSHTerminalView(…)` instantiation and add the `privateKeyPath:` argument. Run:
  ```bash
  grep -rn "SSHTerminalView(" /Users/zeitune/src/zetssh/zetssh/
  ```
  For each call site, add `privateKeyPath: session.privateKeyPath` (or the equivalent variable that holds the `Session`). Example:

  ```swift
  // Before
  SSHTerminalView(host: session.host, port: session.port, username: session.username, sessionId: session.id)

  // After
  SSHTerminalView(
      host:           session.host,
      port:           session.port,
      username:       session.username,
      sessionId:      session.id,
      privateKeyPath: session.privateKeyPath
  )
  ```

- [ ] **5.3** Build and confirm no errors:
  ```bash
  xcodebuild -project /Users/zeitune/src/zetssh/zetssh.xcodeproj \
    -scheme zetssh \
    -destination 'platform=macOS' \
    build 2>&1 | grep -E "error:|BUILD"
  ```

- [ ] **5.4** Commit:
  ```bash
  cd /Users/zeitune/src/zetssh && git add zetssh/Presentation/Terminal/TerminalView.swift && git commit -m "feat(terminal): route to private key auth when session.privateKeyPath is set"
  ```

---

## Task 6 — Smoke test checklist (manual, no XCTest required)

Run the app (`⌘R` in Xcode or product → Run). Verify each item:

- [ ] **6.1** Open "Nova Sessão". Confirm the segmented control "Senha | Chave Privada" appears below the username field.
- [ ] **6.2** Select "Chave Privada". Confirm the password `SecureField` disappears and the key picker row + passphrase field appear.
- [ ] **6.3** Click "Escolher…". Confirm `NSOpenPanel` opens at `~/.ssh/` (or home if `~/.ssh` does not exist). Pick a key file. Confirm the path appears in the row.
- [ ] **6.4** Save the session. Confirm it appears in the sidebar with no crash.
- [ ] **6.5** Select "Senha", save a second session with a password. Confirm both sessions coexist.
- [ ] **6.6** Connect to the key-based session against a real or local SSH server that accepts the key. Confirm the shell prompt appears in the terminal.
- [ ] **6.7** Connect to the password session. Confirm auth still works as before.
- [ ] **6.8** Quit and relaunch the app. Confirm both sessions persist and `privateKeyPath` is restored correctly from GRDB.

---

## Error handling reference

| Scenario | Where it fails | Error thrown | UI message |
|---|---|---|---|
| Key file not readable (wrong path/permissions) | `RealSSHEngine.authenticate(privateKeyPath:)` | `SSHConnectionError.authenticationFailed` | `Connection failed: authenticationFailed` |
| PEM parse fails (wrong passphrase or corrupt file) | `NIOSSHPrivateKey(pemRepresentation:)` | `SSHConnectionError.authenticationFailed` | `Connection failed: authenticationFailed` |
| Server does not offer `publicKey` auth method | `PrivateKeyAuthenticationDelegate` | `nil` offer → NIOSSH closes channel | `Connection failed: …` |
| Engine called while already connecting | `guard connectionState == .idle` | `SSHConnectionError.alreadyConnecting` | `Connection failed: alreadyConnecting` |

---

## File change summary

| File | Change type |
|---|---|
| `Domain/Models/Session.swift` | Add `privateKeyPath: String?` property |
| `Data/Database/AppDatabase.swift` | Add migration v3 (`ALTER TABLE session ADD COLUMN privateKeyPath TEXT`) |
| `Data/Security/KeychainService.swift` | Add `savePassphrase`, `fetchPassphrase`, `deletePassphrase` |
| `Data/Network/RealSSHEngine.swift` | Implement `authenticate(privateKeyPath:passphrase:)` + `PrivateKeyAuthenticationDelegate` |
| `Presentation/Sessions/SessionFormView.swift` | Add `AuthMode` enum, `SessionCredentials` enum, segmented picker, key picker row, passphrase field |
| `Presentation/Terminal/TerminalView.swift` | Add `privateKeyPath` param, route `connect()` to correct auth method |
