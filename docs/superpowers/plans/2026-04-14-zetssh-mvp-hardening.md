# ZetSSH MVP Hardening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Corrigir todos os Critical e Important issues da revisão de código, tornando o ZetSSH seguro, estável e funcional para uso real em infraestrutura.

**Architecture:** Três fases progressivas — Fase 1 resolve bugs de segurança e crashes (P0); Fase 2 melhora robustez e state management (P1); Fase 3 adiciona qualidade de código e testes (P2). Cada fase é independente e produz um app funcional.

**Tech Stack:** Swift 5.0+, SwiftUI/AppKit, SwiftNIO-SSH 0.12.0, GRDB 6.29.3, SwiftTerm 1.13.0, Crypto (transitivo via NIOSSH), macOS 26.2+

**Source root:** `zetssh/zetssh/` (relativo a `/Users/zeitune/src/zetssh/`)

---

## FASE 1 — Segurança & Estabilidade (P0)

---

### Task 1: Modelo KnownHost + Migração GRDB v2

**Files:**
- Create: `zetssh/zetssh/Domain/Models/KnownHost.swift`
- Modify: `zetssh/zetssh/Data/Database/AppDatabase.swift`

- [ ] **Step 1: Criar o modelo KnownHost**

```swift
// zetssh/zetssh/Domain/Models/KnownHost.swift
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
```

- [ ] **Step 2: Registrar a migração v2 em AppDatabase.swift**

Localizar o `var migrator: DatabaseMigrator` e adicionar após o bloco `v1`:

```swift
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
```

- [ ] **Step 3: Commit**

```bash
cd /Users/zeitune/src/zetssh
git add zetssh/zetssh/Domain/Models/KnownHost.swift zetssh/zetssh/Data/Database/AppDatabase.swift
git commit -m "feat: add KnownHost model and GRDB v2 migration"
```

---

### Task 2: HostKeyVerificationService com NSAlert Modal

**Files:**
- Create: `zetssh/zetssh/Data/Security/HostKeyVerificationService.swift`

- [ ] **Step 1: Criar o serviço com lookup GRDB e alertas**

```swift
// zetssh/zetssh/Data/Security/HostKeyVerificationService.swift
import Foundation
import AppKit
import GRDB
import NIOSSH
import Crypto

enum HostKeyVerificationResult {
    case trusted       // host conhecido, fingerprint idêntica → OK
    case userAccepted  // host novo, usuário clicou "Confiar"
    case userRejected  // host novo, usuário cancelou
    case mismatch      // fingerprint mudou → conexão bloqueada
}

@MainActor
final class HostKeyVerificationService {
    static let shared = HostKeyVerificationService()
    private init() {}

    func verify(host: String, port: Int, key: NIOSSHPublicKey) async -> HostKeyVerificationResult {
        let algo = keyAlgorithm(key)
        let fp   = keyFingerprint(key)

        do {
            let existing = try AppDatabase.shared.dbWriter.read { db in
                try KnownHost
                    .filter(Column("host")      == host)
                    .filter(Column("port")      == port)
                    .filter(Column("algorithm") == algo)
                    .fetchOne(db)
            }

            if let known = existing {
                if known.fingerprint == fp { return .trusted }
                await showMismatchAlert(host: host, port: port,
                                        oldFP: known.fingerprint, newFP: fp)
                return .mismatch
            }
        } catch {
            AppLogger.shared.log("KnownHost lookup: \(error)", category: .security, level: .error)
        }

        let accepted = await showUnknownHostAlert(host: host, port: port, algo: algo, fingerprint: fp)
        if accepted {
            let record = KnownHost(host: host, port: port, algorithm: algo,
                                   fingerprint: fp, addedAt: Date())
            try? AppDatabase.shared.dbWriter.write { db in try record.save(db) }
            return .userAccepted
        }
        return .userRejected
    }

    // MARK: - Key Helpers

    private func keyAlgorithm(_ key: NIOSSHPublicKey) -> String {
        // NIOSSHPublicKey description começa com o nome do algoritmo
        let desc = String(describing: key)
        return desc.components(separatedBy: " ").first ?? "unknown"
    }

    private func keyFingerprint(_ key: NIOSSHPublicKey) -> String {
        // SHA256 da representação textual da chave — consistente para a mesma chave
        let data   = Data(String(describing: key).utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - NSAlert Helpers

    private func showUnknownHostAlert(host: String, port: Int,
                                      algo: String, fingerprint: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "Host Desconhecido"
            alert.informativeText = """
            A autenticidade de '\(host):\(port)' não pôde ser estabelecida.

            Algoritmo:   \(algo)
            SHA256:      \(fingerprint.prefix(32))...

            Deseja confiar neste host e continuar?
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Confiar e Conectar")
            alert.addButton(withTitle: "Cancelar")
            continuation.resume(returning: alert.runModal() == .alertFirstButtonReturn)
        }
    }

    private func showMismatchAlert(host: String, port: Int,
                                   oldFP: String, newFP: String) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let alert = NSAlert()
            alert.messageText = "⚠️ ALERTA: Fingerprint do host mudou!"
            alert.informativeText = """
            A fingerprint de '\(host):\(port)' é diferente da armazenada.

            Esperado: \(oldFP.prefix(32))...
            Recebido: \(newFP.prefix(32))...

            Isso pode indicar um ataque man-in-the-middle.
            A conexão foi bloqueada por segurança.
            """
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
            c.resume()
        }
    }
}
```

- [ ] **Step 2: Compilar para verificar erros**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Esperado: `** BUILD SUCCEEDED **` (sem errors)

- [ ] **Step 3: Commit**

```bash
git add zetssh/zetssh/Data/Security/HostKeyVerificationService.swift
git commit -m "feat: add HostKeyVerificationService with NSAlert for unknown/changed host keys"
```

---

### Task 3: Substituir TrustAllServerAuthDelegate por Verificação Real

**Files:**
- Modify: `zetssh/zetssh/Data/Network/RealSSHEngine.swift`

- [ ] **Step 1: Adicionar `SSHConnectionError.hostRejected` ao enum em SSHEngine.swift**

Abrir `zetssh/zetssh/Data/Network/SSHEngine.swift` e adicionar o caso:

```swift
public enum SSHConnectionError: Error {
    case authenticationFailed
    case hostKeyMismatch      // fingerprint mudou
    case hostRejected         // usuário cancelou conexão com host desconhecido
    case alreadyConnecting    // engine não está idle (nova em Task 4)
    case networkTimeout
    case unknown
}
```

- [ ] **Step 2: Criar `HostKeyVerificationDelegate` no final de RealSSHEngine.swift**

Substituir a classe `TrustAllServerAuthDelegate` por:

```swift
private final class HostKeyVerificationDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let host: String
    private let port: Int

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    nonisolated func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        let host = self.host
        let port = self.port
        Task { @MainActor in
            let result = await HostKeyVerificationService.shared.verify(
                host: host, port: port, key: hostKey
            )
            switch result {
            case .trusted, .userAccepted:
                validationCompletePromise.succeed(())
            case .userRejected:
                validationCompletePromise.fail(SSHConnectionError.hostRejected)
            case .mismatch:
                validationCompletePromise.fail(SSHConnectionError.hostKeyMismatch)
            }
        }
    }
}
```

- [ ] **Step 3: Atualizar `establishConnection` para usar o novo delegate**

Localizar a linha `let serverAuth = TrustAllServerAuthDelegate()` em `establishConnection` e substituir por:

```swift
let serverAuth = HostKeyVerificationDelegate(host: host, port: port)
```

- [ ] **Step 4: Remover a classe `TrustAllServerAuthDelegate` (agora obsoleta)**

Deletar o bloco inteiro de `TrustAllServerAuthDelegate` do arquivo.

- [ ] **Step 5: Build + verificar**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Esperado: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add zetssh/zetssh/Data/Network/RealSSHEngine.swift zetssh/zetssh/Data/Network/SSHEngine.swift
git commit -m "security: replace TrustAllServerAuthDelegate with real host key verification"
```

---

### Task 4: State Machine + EventLoopGroup Shutdown Correto

**Files:**
- Modify: `zetssh/zetssh/Data/Network/RealSSHEngine.swift`

- [ ] **Step 1: Adicionar enum de estado e guard de re-entrância**

No início da classe `RealSSHEngine`, adicionar:

```swift
private enum ConnectionState: Equatable {
    case idle, connecting, connected, disconnecting
}
private var connectionState: ConnectionState = .idle
```

- [ ] **Step 2: Proteger `authenticate(password:)` contra re-entrância**

Substituir o início de `authenticate(password:)`:

```swift
public func authenticate(password: String) async throws {
    guard connectionState == .idle else {
        throw SSHConnectionError.alreadyConnecting
    }
    connectionState = .connecting
    let authDelegate = PasswordAuthenticationDelegate(
        username: pendingUsername,
        password: password
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

Fazer o mesmo para `authenticate(privateKeyPath:passphrase:)`:

```swift
public func authenticate(privateKeyPath: URL, passphrase: String?) async throws {
    guard connectionState == .idle else {
        throw SSHConnectionError.alreadyConnecting
    }
    AppLogger.shared.log("Autenticação por chave não implementada.", category: .security, level: .warning)
    throw SSHConnectionError.unknown
}
```

- [ ] **Step 3: Corrigir `disconnect()` para fechar o grupo NIO**

Substituir o método `disconnect()` completo:

```swift
public func disconnect() {
    guard connectionState == .connected || connectionState == .connecting else { return }
    connectionState = .disconnecting
    AppLogger.shared.log("Desconectando SSH...", category: .network, level: .info)
    _ = sshChildChannel?.close()
    _ = channel?.close()
    sshChildChannel = nil
    channel = nil
    group.shutdownGracefully { [weak self] _ in
        DispatchQueue.main.async {
            self?.connectionState = .idle
            AppLogger.shared.log("EventLoopGroup encerrado.", category: .network, level: .info)
        }
    }
}
```

- [ ] **Step 4: Remover `syncShutdownGracefully` do `deinit`**

O `deinit` agora deve ser simplesmente:

```swift
deinit {
    // group já foi encerrado em disconnect()
    // se deinit é chamado sem disconnect, o OS recicla os threads
}
```

Ou removê-lo completamente se estava vazio antes.

- [ ] **Step 5: Expor `connectionState` como propriedade pública readonly**

Adicionar computed property para o ViewModel observar:

```swift
public var isConnected: Bool { connectionState == .connected }
public var isConnecting: Bool { connectionState == .connecting }
```

- [ ] **Step 6: Build**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Esperado: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add zetssh/zetssh/Data/Network/RealSSHEngine.swift
git commit -m "fix: add connection state machine and proper EventLoopGroup shutdown"
```

---

### Task 5: Botão Connect Explícito + UI de Estado de Conexão

**Files:**
- Create: `zetssh/zetssh/Presentation/Sessions/SessionConnectionView.swift`
- Modify: `zetssh/zetssh/Presentation/Sessions/SessionDetailView.swift`
- Modify: `zetssh/zetssh/Presentation/Terminal/TerminalView.swift`

**Objetivo:** O usuário seleciona uma sessão → vê painel de conexão com botão "Connect" → clica → terminal abre. Sem auto-connect.

- [ ] **Step 1: Criar `SessionConnectionView` (painel pré-conexão)**

```swift
// zetssh/zetssh/Presentation/Sessions/SessionConnectionView.swift
import SwiftUI

struct SessionConnectionView: View {
    let session: Session
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "server.rack")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(session.name)
                    .font(.title2.bold())
                Text("\(session.username)@\(session.host):\(session.port)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button(action: onConnect) {
                Label("Conectar", systemImage: "terminal")
                    .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: Reescrever `SessionDetailView` com máquina de estado UI**

```swift
// zetssh/zetssh/Presentation/Sessions/SessionDetailView.swift
import SwiftUI

struct SessionDetailView: View {
    let session: Session?

    @State private var connectionStarted = false

    var body: some View {
        Group {
            if let session {
                if connectionStarted {
                    SSHTerminalView(
                        host:      session.host,
                        port:      session.port,
                        username:  session.username,
                        sessionId: session.id
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                } else {
                    SessionConnectionView(session: session) {
                        connectionStarted = true
                    }
                }
            } else {
                emptyState
            }
        }
        .navigationTitle(session?.name ?? "ZetSSH")
        // Reset ao trocar de sessão
        .onChange(of: session?.id) { _ in
            connectionStarted = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("Selecione uma sessão para conectar")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 3: Remover auto-connect de `SSHTerminalView.makeNSView`**

Em `TerminalView.swift`, retirar o `Task { @MainActor in ... }` de `makeNSView` e adicionar um método público `startConnection()` que o `SSHTerminalView` chama via `onAppear`:

```swift
// Em SSHTerminalView, substituir a parte do Task no makeNSView por:
func makeNSView(context: Context) -> SwiftTerm.TerminalView {
    let termView = SwiftTerm.TerminalView(frame: .zero)
    termView.terminalDelegate = context.coordinator
    context.coordinator.terminalView = termView

    let password = (try? KeychainService.shared.fetchPassword(forSessionId: sessionId)) ?? ""
    let engine   = RealSSHEngine()
    engine.delegate = context.coordinator
    context.coordinator.engine  = engine
    context.coordinator.host     = host
    context.coordinator.port     = port
    context.coordinator.username = username
    context.coordinator.password = password

    // Conexão iniciada via onAppear do SwiftUI (ver updateNSView / onAppear no wrapper)
    return termView
}

func updateNSView(_ nsView: SwiftTerm.TerminalView, context: Context) {}

static func dismantleNSView(_ nsView: SwiftTerm.TerminalView, coordinator: Coordinator) {
    coordinator.engine?.disconnect()
    coordinator.engine = nil
}
```

E no `Coordinator`, adicionar os campos e o método `connect()`:

```swift
final class Coordinator: NSObject {
    var engine:   RealSSHEngine?
    var host:     String = ""
    var port:     Int    = 22
    var username: String = ""
    var password: String = ""
    weak var terminalView: SwiftTerm.TerminalView?

    func connect() {
        guard let engine, let termView = terminalView else { return }
        termView.feed(text: "Connecting to \(username)@\(host):\(port)...\r\n")
        Task { @MainActor in
            do {
                try await engine.connect(host: host, port: port, username: username)
                try await engine.authenticate(password: password)
            } catch {
                termView.feed(text: "\r\n\u{1B}[31mConnection failed: \(error.localizedDescription)\u{1B}[0m\r\n")
            }
        }
    }
}
```

Adicionar o `onAppear` no `SSHTerminalView` como modifier no `SessionDetailView` para chamar `connect()` após o view aparecer. A maneira mais limpa é envolver `SSHTerminalView` numa `struct` que chama `context.coordinator.connect()` no primeiro `updateNSView`:

Adicionar flag ao `Coordinator`:

```swift
var didConnect = false
```

E em `updateNSView`:

```swift
func updateNSView(_ nsView: SwiftTerm.TerminalView, context: Context) {
    guard !context.coordinator.didConnect else { return }
    context.coordinator.didConnect = true
    context.coordinator.connect()
}
```

- [ ] **Step 4: Build**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Esperado: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add zetssh/zetssh/Presentation/Sessions/SessionConnectionView.swift \
        zetssh/zetssh/Presentation/Sessions/SessionDetailView.swift \
        zetssh/zetssh/Presentation/Terminal/TerminalView.swift
git commit -m "feat: add explicit Connect button, remove auto-connect on session selection"
```

---

## FASE 2 — Robustez (P1)

---

### Task 6: AppDatabase — Graceful Error Handling

**Files:**
- Modify: `zetssh/zetssh/Data/Database/AppDatabase.swift`
- Modify: `zetssh/zetssh/App/zetsshApp.swift`

**Objetivo:** Substituir `fatalError` por `Result<AppDatabase, Error>` e apresentar `NSAlert` se o banco falhar ao inicializar.

- [ ] **Step 1: Converter `AppDatabase` para inicializador que pode falhar**

```swift
// AppDatabase.swift — substituir o init privado
final class AppDatabase {
    static var shared: AppDatabase = {
        do {
            return try AppDatabase()
        } catch {
            // Vai ser tratado em zetsshApp antes de usar shared
            fatalError("Falha crítica ao inicializar banco de dados: \(error)")
        }
    }()

    let dbWriter: DatabaseWriter

    static func makeOrAlert() -> AppDatabase? {
        do {
            return try AppDatabase()
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Erro ao inicializar o banco de dados"
                alert.informativeText = error.localizedDescription + "\n\nO aplicativo não pode continuar."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "Sair")
                alert.runModal()
                NSApp.terminate(nil)
            }
            return nil
        }
    }

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

        let config = Configuration()
        _ = try KeychainService.shared.getOrCreateDatabaseEncryptionKey()
        dbWriter = try DatabasePool(path: databaseURL.path, configuration: config)
        try migrator.migrate(dbWriter)

        AppLogger.shared.log("Database inicializado em \(databaseURL.path)", category: .database, level: .info)
    }

    // ... migrator permanece igual
}
```

- [ ] **Step 2: Inicializar banco em `zetsshApp` antes de montar a UI**

```swift
// App/zetsshApp.swift
import SwiftUI
import AppKit

@main
struct zetsshApp: App {
    init() {
        // Garante que o banco está OK antes da UI montar
        _ = AppDatabase.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
```

- [ ] **Step 3: Build**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 4: Commit**

```bash
git add zetssh/zetssh/Data/Database/AppDatabase.swift zetssh/zetssh/App/zetsshApp.swift
git commit -m "fix: replace fatalError in AppDatabase with graceful NSAlert on failure"
```

---

### Task 7: SessionViewModel com ValueObservation GRDB

**Files:**
- Create: `zetssh/zetssh/Presentation/Sessions/SessionViewModel.swift`
- Modify: `zetssh/zetssh/Presentation/ContentView.swift`
- Modify: `zetssh/zetssh/Presentation/Sessions/SidebarView.swift`

**Objetivo:** Eliminar o `@Binding var sessions` manual; usar GRDB `ValueObservation` que notifica automaticamente em qualquer mudança.

- [ ] **Step 1: Criar `SessionViewModel`**

```swift
// zetssh/zetssh/Presentation/Sessions/SessionViewModel.swift
import Foundation
import GRDB
import Combine

@MainActor
final class SessionViewModel: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published var errorMessage: String?

    private var observation: AnyDatabaseCancellable?

    init() {
        startObserving()
    }

    private func startObserving() {
        let observation = ValueObservation.tracking { db in
            try Session.fetchAll(db)
        }
        self.observation = observation.start(
            in: AppDatabase.shared.dbWriter,
            scheduling: .immediate,
            onError: { [weak self] error in
                self?.errorMessage = "Erro ao carregar sessões: \(error.localizedDescription)"
            },
            onChange: { [weak self] sessions in
                self?.sessions = sessions
            }
        )
    }

    func save(_ session: Session, password: String) {
        var s = session
        do {
            try AppDatabase.shared.dbWriter.write { db in try s.save(db) }
            if !password.isEmpty {
                try KeychainService.shared.save(password: password, forSessionId: s.id)
            }
        } catch {
            errorMessage = "Erro ao salvar sessão: \(error.localizedDescription)"
        }
    }

    func delete(_ session: Session) {
        do {
            try AppDatabase.shared.dbWriter.write { db in try session.delete(db) }
            try KeychainService.shared.deletePassword(forSessionId: session.id)
        } catch {
            errorMessage = "Erro ao deletar sessão: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 2: Simplificar `ContentView` para usar o ViewModel**

```swift
// zetssh/zetssh/Presentation/ContentView.swift
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SessionViewModel()
    @State private var selectedSessionId: UUID?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                viewModel:         viewModel,
                selectedSessionId: $selectedSessionId
            )
        } detail: {
            let session = viewModel.sessions.first { $0.id == selectedSessionId }
            SessionDetailView(session: session)
        }
        .alert("Erro", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
```

- [ ] **Step 3: Simplificar `SidebarView` para usar o ViewModel**

```swift
// zetssh/zetssh/Presentation/Sessions/SidebarView.swift
import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: SessionViewModel
    @Binding var selectedSessionId: UUID?
    @State private var showingAddSession = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSessionId) {
                Section("Sessions") {
                    ForEach(viewModel.sessions) { session in
                        NavigationLink(value: session.id) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.name).font(.headline)
                                Text("\(session.username)@\(session.host):\(session.port)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button("Deletar", role: .destructive) {
                                viewModel.delete(session)
                                if selectedSessionId == session.id { selectedSessionId = nil }
                            }
                        }
                    }
                    .onDelete(perform: deleteSessions)
                }
            }
            .onDeleteCommand {
                if let id = selectedSessionId,
                   let session = viewModel.sessions.first(where: { $0.id == id }) {
                    viewModel.delete(session)
                    selectedSessionId = nil
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                Button { showingAddSession = true } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain).padding(8)

                Spacer()

                Button {
                    if let id = selectedSessionId,
                       let session = viewModel.sessions.first(where: { $0.id == id }) {
                        viewModel.delete(session)
                        selectedSessionId = nil
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.plain).padding(8)
                .disabled(selectedSessionId == nil)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .navigationTitle("ZetSSH")
        .sheet(isPresented: $showingAddSession) {
            SessionFormView { newSession, password in
                viewModel.save(newSession, password: password)
            }
        }
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = viewModel.sessions[index]
            viewModel.delete(session)
            if selectedSessionId == session.id { selectedSessionId = nil }
        }
    }
}
```

- [ ] **Step 4: Build**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Esperado: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add zetssh/zetssh/Presentation/Sessions/SessionViewModel.swift \
        zetssh/zetssh/Presentation/ContentView.swift \
        zetssh/zetssh/Presentation/Sessions/SidebarView.swift
git commit -m "refactor: replace manual @Binding sessions with GRDB ValueObservation ViewModel"
```

---

### Task 8: Validação de Formulário de Sessão

**Files:**
- Modify: `zetssh/zetssh/Presentation/Sessions/SessionFormView.swift`

- [ ] **Step 1: Adicionar validação de porta e trim ao SessionFormView**

```swift
// zetssh/zetssh/Presentation/Sessions/SessionFormView.swift
import SwiftUI

struct SessionFormView: View {
    @Environment(\.dismiss) var dismiss

    @State private var name:     String = ""
    @State private var host:     String = ""
    @State private var port:     String = "22"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var portError: String?

    var onSave: (Session, String) -> Void

    private var trimmedHost:     String { host.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedUsername: String { username.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var portInt: Int? {
        guard let p = Int(port.trimmingCharacters(in: .whitespaces)),
              (1...65535).contains(p) else { return nil }
        return p
    }
    private var isFormValid: Bool {
        !trimmedHost.isEmpty && !trimmedUsername.isEmpty && portInt != nil
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
                SecureField("Senha", text: $password)
                    .help("Armazenada com segurança no Keychain do macOS")
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
        .frame(minWidth: 420, minHeight: 300)
    }

    private func validatePort() {
        let trimmed = port.trimmingCharacters(in: .whitespaces)
        if let p = Int(trimmed) {
            portError = (1...65535).contains(p) ? nil : "Porta deve estar entre 1 e 65535"
        } else {
            portError = trimmed.isEmpty ? nil : "Porta inválida"
        }
    }

    private func save() {
        guard let portValue = portInt else { return }
        let sessionName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newSession = Session(
            id:       UUID(),
            folderId: nil,
            name:     sessionName.isEmpty ? trimmedHost : sessionName,
            host:     trimmedHost,
            port:     portValue,
            username: trimmedUsername
        )
        onSave(newSession, password)
        dismiss()
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
git add zetssh/zetssh/Presentation/Sessions/SessionFormView.swift
git commit -m "feat: add port range validation and whitespace trimming to SessionFormView"
```

---

## FASE 3 — Qualidade (P2)

---

### Task 9: SSHEngine Protocol — Adicionar sendData e resize

**Files:**
- Modify: `zetssh/zetssh/Data/Network/SSHEngine.swift`
- Modify: `zetssh/zetssh/Presentation/Terminal/TerminalView.swift`

**Objetivo:** O `Coordinator` deve usar `any SSHEngine` em vez de `RealSSHEngine` concreto.

- [ ] **Step 1: Estender o protocolo SSHEngine**

```swift
// SSHEngine.swift — adicionar ao protocolo:
public protocol SSHEngine {
    func connect(host: String, port: Int, username: String) async throws
    func authenticate(password: String) async throws
    func authenticate(privateKeyPath: URL, passphrase: String?) async throws
    func disconnect()
    func sendData(_ data: [UInt8])
    func resize(cols: Int, rows: Int)
    var isConnected: Bool { get }
    var isConnecting: Bool { get }
}
```

- [ ] **Step 2: Atualizar o `Coordinator` em TerminalView.swift**

```swift
// Em SSHTerminalView.Coordinator, trocar o tipo:
var engine: (any SSHEngine)?
```

- [ ] **Step 3: Garantir que `LibSSH2WrapperMock` ainda compila (adicionar stubs)**

```swift
// Em SSHEngine.swift, dentro de LibSSH2WrapperMock:
#if DEBUG
public final class LibSSH2WrapperMock: SSHEngine {
    public init() {}
    public func connect(host: String, port: Int, username: String) async throws { }
    public func authenticate(password: String) async throws { }
    public func authenticate(privateKeyPath: URL, passphrase: String?) async throws { }
    public func disconnect() { }
    public func sendData(_ data: [UInt8]) { }
    public func resize(cols: Int, rows: Int) { }
    public var isConnected: Bool { false }
    public var isConnecting: Bool { false }
}
#endif
```

- [ ] **Step 4: Build**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 5: Commit**

```bash
git add zetssh/zetssh/Data/Network/SSHEngine.swift zetssh/zetssh/Presentation/Terminal/TerminalView.swift
git commit -m "refactor: add sendData/resize to SSHEngine protocol, use protocol type in Coordinator"
```

---

### Task 10: Limpeza de Entitlements e Dead Code

**Files:**
- Modify: `zetssh/zetssh/zetssh.entitlements`
- Modify: `zetssh/zetssh/Data/Network/SSHEngine.swift` (remover mock de prod se não feito acima)
- Delete or archive: `zetssh/zetssh/Presentation/Components/PrimaryButton.swift`

- [ ] **Step 1: Remover `network.server` do entitlements**

```xml
<!-- zetssh.entitlements — remover a linha: -->
<key>com.apple.security.network.server</key>
<true/>
```

O arquivo final deve ficar:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.zetssh.credentials</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 2: Build + verificar que sandbox ainda funciona**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit final de limpeza**

```bash
git add zetssh/zetssh/zetssh.entitlements
git commit -m "chore: remove unnecessary network.server entitlement, wrap mock in #if DEBUG"
```

---

## Resumo de Arquivos por Fase

| Fase | Arquivos Criados | Arquivos Modificados |
|------|-----------------|---------------------|
| P0 | `KnownHost.swift`, `HostKeyVerificationService.swift`, `SessionConnectionView.swift` | `AppDatabase.swift`, `SSHEngine.swift`, `RealSSHEngine.swift`, `SessionDetailView.swift`, `TerminalView.swift` |
| P1 | `SessionViewModel.swift` | `AppDatabase.swift`, `zetsshApp.swift`, `ContentView.swift`, `SidebarView.swift`, `SessionFormView.swift` |
| P2 | — | `SSHEngine.swift`, `TerminalView.swift`, `zetssh.entitlements` |

## Ordem de Execução

Executar as tasks nesta ordem exata. Cada task tem build + commit próprio. Não pular commits.

Tasks: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10
