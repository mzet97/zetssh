# ZetSSH — Plano de Execução Completo

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Completar o ZetSSH como cliente SSH macOS profissional — corrigindo bugs de UX, integrando SFTP real via NIO e criptografando o banco de dados com SQLCipher.

**Architecture:** O app segue Clean Architecture (Domain → Data → Presentation). O motor SSH (`RealSSHEngine`) já está integrado ao UI via `SSHTerminalView`. As tarefas expandem sobre essa base: adicionam estado de conexão bidirecional, completam a integração SFTP e habilitam a criptografia do SQLite.

**Tech Stack:** Swift 6, SwiftUI + AppKit, SwiftNIO-SSH, GRDB + SQLCipher, SwiftTerm, Keychain Services, macOS 26.2+

---

## Mapa de Arquivos

| Arquivo | Responsabilidade |
|---|---|
| `Data/Network/RealSSHEngine.swift` | Motor SSH NIO — keepalive, send/receive, SFTP channel |
| `Data/Network/SSHEngine.swift` | Protocolo + erros |
| `Data/Network/SFTPClient.swift` | Implementação SFTPv3 sobre NIO |
| `Data/Network/SFTPEngine.swift` | Protocolo SFTP |
| `Data/Database/AppDatabase.swift` | GRDB singleton + migrations |
| `Data/Security/KeychainService+DBKey.swift` | Chave de 256-bit para SQLCipher |
| `Domain/Models/ActiveSession.swift` | Estado de aba — adicionar `connectionState` |
| `Presentation/Sessions/SessionDetailView.swift` | UI de sessão — toolbar Connect/Disconnect |
| `Presentation/Sessions/TabBarView.swift` | Barra de abas — indicador de estado |
| `Presentation/Sessions/TabsViewModel.swift` | Gerência de abas — propagar estado |
| `Presentation/Terminal/TerminalView.swift` | `SSHTerminalView` + callbacks de estado |
| `Presentation/SFTP/FileBrowserView.swift` | UI do browser SFTP |
| `Presentation/SFTP/FileBrowserViewModel.swift` | ViewModel SFTP |

---

## Task 1: Corrigir Sendable warnings em RealSSHEngine

**Files:**
- Modify: `zetssh/Data/Network/RealSSHEngine.swift`

- [ ] **Step 1: Identificar os warnings exatos**

No Xcode, abra o projeto e compile com ⌘B. Os 2 warnings de Sendable aparecem na área de issues. Anote as linhas exatas — tipicamente são no `HostKeyVerificationDelegate` (que usa `Task { @MainActor in }` dentro de uma closure `nonisolated`) ou nas delegates de autenticação.

- [ ] **Step 2: Corrigir o HostKeyVerificationDelegate**

A pattern `Task { @MainActor in ... }` dentro de `nonisolated` pode gerar warning em Swift 6. Substituir por `@Sendable` explícito na closure:

```swift
nonisolated func validateHostKey(
    hostKey: NIOSSHPublicKey,
    validationCompletePromise: EventLoopPromise<Void>
) {
    let host = self.host
    let port = self.port
    Task { @MainActor [host, port] in
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
```

- [ ] **Step 3: Corrigir warnings restantes**

Se ainda houver warnings, o padrão é o mesmo: capturar valores imutáveis antes de entrar em closures e anotar como `@Sendable` onde necessário.

- [ ] **Step 4: Confirmar zero warnings**

Compile ⌘B. Área de issues deve mostrar 0 warnings de Sendable.

- [ ] **Step 5: Commit**

```bash
git add zetssh/Data/Network/RealSSHEngine.swift
git commit -m "fix: resolve Sendable warnings in RealSSHEngine (Swift 6 concurrency)"
```

---

## Task 2: Reconexão após timeout ou disconnect

**Problema:** quando `onDisconnected()` ou `onError(.connectionTimedOut)` dispara, `connectionStarted` em `SessionDetailView` permanece `true` — o terminal fica exibindo a sessão morta sem forma de reconectar.

**Files:**
- Modify: `zetssh/Presentation/Terminal/TerminalView.swift`
- Modify: `zetssh/Presentation/Sessions/SessionDetailView.swift`

- [ ] **Step 1: Adicionar callback `onConnectionEnded` em `SSHTerminalView`**

Em `TerminalView.swift`, adicione a propriedade e dispare-a nos dois eventos de encerramento:

```swift
struct SSHTerminalView: NSViewRepresentable {
    let host:            String
    let port:            Int
    let username:        String
    let sessionId:       UUID
    let privateKeyPath:  String?
    var onConnectionEnded: (() -> Void)? = nil   // ← novo

    // ...

    final class Coordinator: NSObject {
        var onConnectionEnded: (() -> Void)?
        // resto igual
    }

    func makeNSView(context: Context) -> SwiftTerm.TerminalView {
        // ...
        context.coordinator.onConnectionEnded = onConnectionEnded  // ← atribuir
        return termView
    }
}
```

- [ ] **Step 2: Disparar o callback em `onError` e `onDisconnected`**

```swift
func onError(_ error: Error) {
    let text: String
    if case SSHConnectionError.connectionTimedOut = error {
        text = "\r\n\u{1B}[33m[Conexão encerrada: servidor não respondeu por 3 minutos.]\u{1B}[0m\r\n" +
               "\u{1B}[33m[Selecione a sessão na barra lateral para reconectar.]\u{1B}[0m\r\n"
    } else {
        text = "\r\n\u{1B}[31mErro SSH: \(error.localizedDescription)\u{1B}[0m\r\n"
    }
    terminalView?.feed(text: text)
    // Dispara após breve delay para o usuário ler a mensagem
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
        self?.onConnectionEnded?()
    }
}

func onDisconnected() {
    terminalView?.feed(
        text: "\r\n\u{1B}[33m[Conexão encerrada. Selecione a sessão para reconectar.]\u{1B}[0m\r\n"
    )
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
        self?.onConnectionEnded?()
    }
}
```

- [ ] **Step 3: Usar o callback em `SessionDetailView`**

```swift
// Em SessionDetailView, substituir o bloco SSHTerminalView:
SSHTerminalView(
    host:           session.host,
    port:           session.port,
    username:       session.username,
    sessionId:      session.id,
    privateKeyPath: session.privateKeyPath,
    onConnectionEnded: {
        connectionStarted = false   // volta para SessionConnectionView
    }
)
.frame(maxWidth: .infinity, maxHeight: .infinity)
.background(Color.black)
```

- [ ] **Step 4: Testar o fluxo**

Compile e rode. Abra uma sessão. No terminal, execute `sleep 200` e depois mate a conexão de rede (desative Wi-Fi por 3+ minutos). Após o timeout, o app deve retornar automaticamente para a tela de "Conectar".

- [ ] **Step 5: Commit**

```bash
git add zetssh/Presentation/Terminal/TerminalView.swift \
        zetssh/Presentation/Sessions/SessionDetailView.swift
git commit -m "fix: return to connect screen after SSH disconnect or timeout"
```

---

## Task 3: Botão Disconnect na toolbar

**Files:**
- Modify: `zetssh/Presentation/Sessions/SessionDetailView.swift`
- Modify: `zetssh/Presentation/Terminal/TerminalView.swift`

- [ ] **Step 1: Expor `disconnect()` via callback em `SSHTerminalView`**

Adicione uma propriedade `onDisconnectRequest` que o `Coordinator` armazena e expõe ao exterior. `SessionDetailView` chama essa função quando o usuário pressiona "Desconectar":

```swift
struct SSHTerminalView: NSViewRepresentable {
    // propriedades existentes...
    var onConnectionEnded: (() -> Void)? = nil
    var disconnectAction: ((SSHTerminalView.Coordinator) -> Void)? = nil

    final class Coordinator: NSObject {
        // ...
        func disconnect() {
            engine?.disconnect()
        }
    }
}
```

Alternativamente (mais simples), exponha o `engine` diretamente ao `SessionDetailView` via `@Binding` ou use um objeto `@StateObject` compartilhado.

**Abordagem recomendada — usar `@StateObject` para o engine:**

Crie `SSHSessionController` em `Presentation/Sessions/`:

```swift
// Presentation/Sessions/SSHSessionController.swift
import Foundation

@MainActor
final class SSHSessionController: ObservableObject {
    @Published private(set) var isConnected = false
    private var engine: RealSSHEngine?

    func start(host: String, port: Int, username: String, sessionId: UUID, privateKeyPath: String?) {
        // ...conecta usando RealSSHEngine
    }

    func disconnect() {
        engine?.disconnect()
        isConnected = false
    }
}
```

*Nota: Esta refatoração é mais profunda. Se preferir manter a arquitetura atual, use o callback simples abaixo.*

**Abordagem simples (sem refatorar):** use um `@State var engineRef: (any SSHEngine)?` em `SessionDetailView` e passe-o via closure de `SSHTerminalView`:

```swift
// Em SSHTerminalView.makeNSView:
context.coordinator.onEngineReady = onEngineReady

// Em SessionDetailView:
@State private var activeEngine: (any SSHEngine)?

SSHTerminalView(
    // ...
    onEngineReady: { engine in activeEngine = engine },
    onConnectionEnded: { connectionStarted = false; activeEngine = nil }
)
```

- [ ] **Step 2: Adicionar `ToolbarItem` de Disconnect em `SessionDetailView`**

```swift
.toolbar {
    ToolbarItem(placement: .automatic) {
        Button {
            showingTerminalSettings = true
        } label: {
            Label("Aparência", systemImage: "paintpalette")
        }
        .help("Configurar tema e fonte do terminal")
    }
    ToolbarItem(placement: .automatic) {
        Button {
            showingSFTP = true
        } label: {
            Label("SFTP", systemImage: "folder.badge.gearshape")
        }
        .help("Abrir File Browser SFTP")
        .disabled(!connectionStarted)
    }
    // ← novo
    ToolbarItem(placement: .automatic) {
        Button(role: .destructive) {
            activeEngine?.disconnect()
            connectionStarted = false
            activeEngine = nil
        } label: {
            Label("Desconectar", systemImage: "xmark.circle")
        }
        .help("Encerrar sessão SSH")
        .disabled(!connectionStarted)
    }
}
```

- [ ] **Step 3: Testar**

Rode o app. Conecte a um servidor. O botão "Desconectar" deve aparecer habilitado na toolbar. Clicar deve retornar para a tela de `SessionConnectionView` imediatamente.

- [ ] **Step 4: Commit**

```bash
git add zetssh/Presentation/Sessions/SessionDetailView.swift \
        zetssh/Presentation/Terminal/TerminalView.swift
git commit -m "feat: add Disconnect toolbar button to active SSH sessions"
```

---

## Task 4: Indicador de estado da conexão nas abas

**Files:**
- Modify: `zetssh/Domain/Models/ActiveSession.swift`
- Modify: `zetssh/Presentation/Sessions/TabsViewModel.swift`
- Modify: `zetssh/Presentation/Sessions/TabBarView.swift`

- [ ] **Step 1: Ler `ActiveSession.swift` e adicionar estado**

Abra `zetssh/Domain/Models/ActiveSession.swift` e adicione:

```swift
enum TabConnectionState {
    case idle        // nunca conectou
    case connecting
    case connected
    case disconnected
}

// Em ActiveSession:
@Published var connectionState: TabConnectionState = .idle
```

- [ ] **Step 2: Adicionar método em `TabsViewModel` para atualizar estado**

```swift
// Em TabsViewModel:
func updateConnectionState(_ state: TabConnectionState, forTabId id: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
    tabs[index].connectionState = state
}
```

- [ ] **Step 3: Propagar estado de `SessionDetailView` para `TabsViewModel`**

`SessionDetailView` precisa receber o `tabId` e uma referência ao `TabsViewModel`. Adicione ao `MultiSessionView`:

```swift
ForEach(tabsVM.tabs) { tab in
    SessionDetailView(
        session: tab.session,
        tabId: tab.id,
        tabsVM: tabsVM
    )
    .opacity(tabsVM.selectedTabId == tab.id ? 1 : 0)
    // ...
}
```

Em `SessionDetailView`, observe `connectionStarted` e atualize o `TabsViewModel`:

```swift
.onChange(of: connectionStarted) { started in
    tabsVM.updateConnectionState(started ? .connected : .disconnected, forTabId: tabId)
}
```

- [ ] **Step 4: Exibir indicador na `TabBarView`**

```swift
// Dentro de tabButton(for:):
HStack(spacing: 4) {
    // indicador de estado
    Circle()
        .fill(tab.connectionState == .connected ? Color.green : 
              tab.connectionState == .connecting ? Color.yellow :
              tab.connectionState == .disconnected ? Color.red : Color.clear)
        .frame(width: 6, height: 6)

    Text(tab.label)
        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: 140, alignment: .leading)

    // botão de fechar (existente)
}
```

- [ ] **Step 5: Testar**

Rode o app. Abra duas sessões. A aba conectada deve mostrar ponto verde; aba desconectada após timeout, ponto vermelho.

- [ ] **Step 6: Commit**

```bash
git add zetssh/Domain/Models/ActiveSession.swift \
        zetssh/Presentation/Sessions/TabsViewModel.swift \
        zetssh/Presentation/Sessions/TabBarView.swift \
        zetssh/Presentation/Sessions/SessionDetailView.swift \
        zetssh/Presentation/Sessions/MultiSessionView.swift
git commit -m "feat: add connection state indicator to tab bar"
```

---

## Task 5: SFTP real via NIO

**Contexto:** `SFTPClient.swift` tem a estrutura SFTPv3 mas os primitivos retornam `throw SFTPError.protocolError`. Precisamos implementar o envio/recebimento de pacotes SFTPv3 sobre um canal NIO do tipo `subsystem("sftp")`.

**Files:**
- Modify: `zetssh/Data/Network/SFTPClient.swift`
- Modify: `zetssh/Data/Network/RealSSHEngine.swift` (adicionar `openSFTPClient()`)
- Modify: `zetssh/Presentation/Sessions/SessionDetailView.swift` (substituir placeholder)
- Modify: `zetssh/Presentation/SFTP/FileBrowserViewModel.swift`

- [ ] **Step 1: Criar `SFTPChannelHandler` em `SFTPClient.swift`**

O handler recebe dados do canal SSH, acumula em buffer e resolve promises pendentes por `requestId`:

```swift
// Adicionar em SFTPClient.swift (antes da classe SFTPClient):

private final class SFTPChannelHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn  = SSHChannelData
    typealias InboundOut = SSHChannelData
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private var buffer = ByteBuffer()
    private var pendingReplies: [UInt32: CheckedContinuation<ByteBuffer, Error>] = [:]
    private let lock = NSLock()

    // Registra uma promise para requestId
    func register(requestId: UInt32, continuation: CheckedContinuation<ByteBuffer, Error>) {
        lock.lock(); defer { lock.unlock() }
        pendingReplies[requestId] = continuation
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(let buf) = channelData.data else { return }
        buffer.writeImmutableBuffer(buf)
        processBuffer()
    }

    private func processBuffer() {
        // Cada pacote SFTP: uint32 length + uint8 type + uint32 requestId + payload
        while buffer.readableBytes >= 9 {
            guard let length = buffer.getInteger(at: buffer.readerIndex, as: UInt32.self) else { break }
            let packetSize = Int(length) + 4
            guard buffer.readableBytes >= packetSize else { break }
            var packet = buffer.readSlice(length: packetSize)!
            packet.moveReaderIndex(forwardBy: 4) // skip length
            guard let _type = packet.readInteger(as: UInt8.self),
                  let reqId  = packet.readInteger(as: UInt32.self) else { break }
            _ = _type
            lock.lock()
            let cont = pendingReplies.removeValue(forKey: reqId)
            lock.unlock()
            cont?.resume(returning: packet)
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buf = unwrapOutboundIn(data)
        let channelData = SSHChannelData(type: .channel, data: .byteBuffer(buf))
        context.write(wrapOutboundOut(channelData), promise: promise)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        lock.lock()
        let pending = pendingReplies
        pendingReplies.removeAll()
        lock.unlock()
        pending.values.forEach { $0.resume(throwing: error) }
        context.fireErrorCaught(error)
    }
}
```

- [ ] **Step 2: Adicionar `openSFTPClient()` em `RealSSHEngine`**

```swift
// Em RealSSHEngine.swift, após openSFTPChannel():
public func openSFTPClient() async throws -> SFTPClient {
    guard let conn = channel, connectionState == .connected else {
        throw SSHConnectionError.unknown
    }
    let sftpChannel = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Channel, Error>) in
        let promise = conn.eventLoop.makePromise(of: Channel.self)
        promise.futureResult.whenComplete { result in
            switch result {
            case .success(let ch): continuation.resume(returning: ch)
            case .failure(let err): continuation.resume(throwing: err)
            }
        }
        conn.pipeline.handler(type: NIOSSHHandler.self).whenSuccess { handler in
            handler.createChannel(promise, channelType: .session) { ch, _ in
                ch.pipeline.addHandler(SFTPChannelHandler())
            }
        }
    }
    // Abrir subsistema SFTP
    try await sftpChannel.triggerUserOutboundEvent(
        SSHChannelRequestEvent.SubsystemRequest(subsystem: "sftp", wantReply: true)
    ).get()
    // Enviar SSH_FXP_INIT (type=1, version=3)
    var initBuf = sftpChannel.allocator.buffer(capacity: 9)
    initBuf.writeInteger(UInt32(5))   // length
    initBuf.writeInteger(UInt8(1))    // SSH_FXP_INIT
    initBuf.writeInteger(UInt32(0))   // requestId placeholder (INIT não usa)
    initBuf.writeInteger(UInt32(3))   // version 3
    try await sftpChannel.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(initBuf))).get()
    return SFTPClient(channel: sftpChannel)
}
```

- [ ] **Step 3: Implementar `sendPacketAwaitHandle` em `SFTPClient`**

```swift
private func sendPacketAwaitHandle(type: UInt8, payload: (inout ByteBuffer) -> Void) async throws -> Data {
    let reqId = nextRequestId()
    var body = channel.allocator.buffer(capacity: 64)
    body.writeInteger(type)
    body.writeInteger(reqId)
    payload(&body)
    var packet = channel.allocator.buffer(capacity: body.readableBytes + 4)
    packet.writeInteger(UInt32(body.readableBytes))
    packet.writeImmutableBuffer(body)

    let reply: ByteBuffer = try await withCheckedThrowingContinuation { continuation in
        channel.pipeline.handler(type: SFTPChannelHandler.self).whenSuccess { handler in
            handler.register(requestId: reqId, continuation: continuation)
        }
        channel.writeAndFlush(packet, promise: nil)
    }
    var r = reply
    guard let handle = r.readBytes(length: r.readableBytes) else {
        throw SFTPError.protocolError("Empty handle response")
    }
    return Data(handle)
}
```

- [ ] **Step 4: Implementar os demais primitivos (`sendPacketAwaitStatus`, `sendPacketAwaitData`, `sendPacketAwaitNameList`, `sendPacketAwaitAttrs`) seguindo o mesmo padrão do Step 3, ajustando o parsing da resposta conforme o tipo SFTPv3.**

Referência dos tipos de resposta SFTPv3:
- `SSH_FXP_STATUS` (101) — `sendPacketAwaitStatus` → lê uint32 status code
- `SSH_FXP_HANDLE` (102) — `sendPacketAwaitHandle` → lê string handle
- `SSH_FXP_DATA` (103) — `sendPacketAwaitData` → lê string data
- `SSH_FXP_NAME` (104) — `sendPacketAwaitNameList` → lê uint32 count + N × (filename + longname + attrs)
- `SSH_FXP_ATTRS` (105) — `sendPacketAwaitAttrs` → lê attrs struct (flags + size)

- [ ] **Step 5: Atualizar `FileBrowserViewModel` para usar o engine real**

```swift
// FileBrowserViewModel.swift
@MainActor
final class FileBrowserViewModel: ObservableObject {
    @Published var items: [RemoteFileItem] = []
    @Published var currentPath = "/"
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var sftp: SFTPClient?
    private let engine: RealSSHEngine

    init(engine: RealSSHEngine) {
        self.engine = engine
    }

    func connect() async {
        do {
            sftp = try await engine.openSFTPClient()
            await loadDirectory(path: "/")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadDirectory(path: String) async {
        guard let sftp else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await sftp.listDirectory(path: path)
            currentPath = path
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 6: Substituir o placeholder em `SessionDetailView`**

Remover `Text("SFTP Browser — requer integração NIO (próxima iteração)")` e substituir por:

```swift
.sheet(isPresented: $showingSFTP) {
    if let engine = activeEngine as? RealSSHEngine {
        FileBrowserView(viewModel: FileBrowserViewModel(engine: engine))
            .frame(minWidth: 560, minHeight: 480)
    }
}
```

- [ ] **Step 7: Testar listagem de diretório**

Conecte a um servidor SSH. Abra o SFTP browser. Navegue para `/tmp`. Deve listar os arquivos do servidor.

- [ ] **Step 8: Commit**

```bash
git add zetssh/Data/Network/SFTPClient.swift \
        zetssh/Data/Network/RealSSHEngine.swift \
        zetssh/Presentation/SFTP/ \
        zetssh/Presentation/Sessions/SessionDetailView.swift
git commit -m "feat: implement SFTPv3 over NIO-SSH with file browser UI"
```

---

## Task 6: SQLCipher — criptografia do banco de dados

**Contexto:** A chave de 256-bit já está sendo gerada e salva no Keychain (`KeychainService+DBKey.swift`). O banco usa GRDB sem criptografia. Precisamos trocar para `GRDBCipher` e passar a chave.

**Files:**
- Modify: `zetssh.xcodeproj/project.pbxproj` (trocar dependência GRDB → GRDBCipher)
- Modify: `zetssh/Data/Database/AppDatabase.swift`
- Modify: `zetssh/Data/Security/KeychainService+DBKey.swift`

- [ ] **Step 1: Verificar dependência GRDB atual no projeto**

No Xcode, abra **Package Dependencies** (menu File → Packages → ...) e localize `GRDB.swift`. Anote a URL e versão usadas.

- [ ] **Step 2: Substituir `GRDB` por `GRDBCipher` no Package.swift ou no Xcode**

No Xcode, selecione o target `zetssh` → **Frameworks, Libraries, and Embedded Content** → remova `GRDB` e adicione `GRDBCipher` do mesmo repositório `https://github.com/groue/GRDB.swift`:

O produto correto é `GRDBCipher` (não `GRDB`) — ele inclui a amalgamação do SQLCipher.

Também atualize todos os imports no projeto:
```bash
# Verificar quais arquivos importam GRDB
grep -r "import GRDB" zetssh/
```
Troque `import GRDB` por `import GRDB` — o nome do módulo continua `GRDB`, apenas o produto linkado muda.

- [ ] **Step 3: Ler `KeychainService+DBKey.swift`**

Leia o arquivo para confirmar a assinatura exata do método que retorna a chave:

```swift
// Esperado:
static func databaseEncryptionKey() throws -> Data  // 32 bytes
```

- [ ] **Step 4: Atualizar `AppDatabase.swift` para passar a chave**

```swift
// Em AppDatabase.init():
private init() {
    do {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbDir = appSupport.appendingPathComponent("ZetSSH", isDirectory: true)
        try fm.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbURL = dbDir.appendingPathComponent("zetssh.db")

        var config = Configuration()
        config.prepareDatabase { db in
            // Busca a chave de 32 bytes do Keychain
            let keyData = try KeychainService.shared.databaseEncryptionKey()
            // SQLCipher usa chave como hex string ou raw key pragma
            let keyHex = keyData.map { String(format: "%02x", $0) }.joined()
            try db.execute(sql: "PRAGMA key = \"x'\(keyHex)'\"")
        }

        dbWriter = try DatabasePool(path: dbURL.path, configuration: config)
        try runMigrations()
    } catch {
        AppLogger.shared.log("AppDatabase init falhou: \(error)", category: .database, level: .fault)
        fatalError("AppDatabase init: \(error)")
    }
}
```

- [ ] **Step 5: Tratar banco existente não-criptografado**

Se o app já tem dados sem SQLCipher, o banco existente falhará ao abrir com chave. Adicione migração de conversão em `runMigrations()` ou apague o banco na primeira abertura com chave:

```swift
config.prepareDatabase { db in
    let keyData = try KeychainService.shared.databaseEncryptionKey()
    let keyHex = keyData.map { String(format: "%02x", $0) }.joined()
    do {
        try db.execute(sql: "PRAGMA key = \"x'\(keyHex)'\"")
    } catch {
        // Banco existente sem criptografia — apaga para recriar
        AppLogger.shared.log(
            "Banco incompatível detectado, recriando.", category: .database, level: .warning
        )
        throw error
    }
}
```

O handler `recover(error:)` em `DatabasePool` pode ser usado para apagar e recriar automaticamente:
```swift
config.readonly = false
// Após criar o pool:
// Se falhar, apagar e tentar novamente sem dados
```

- [ ] **Step 6: Compilar e testar**

Compile ⌘B. Lance o app. Abra Activity Monitor → Console para verificar logs do `AppDatabase`. Crie uma sessão SSH e confirme que persiste após reiniciar o app.

- [ ] **Step 7: Commit**

```bash
git add zetssh/Data/Database/AppDatabase.swift \
        zetssh.xcodeproj/project.pbxproj
git commit -m "feat: encrypt SQLite database with SQLCipher using Keychain-derived key"
```

---

## Ordem de execução recomendada

```
Task 1 (Sendable)     →  15 min  — sem risco, só qualidade
Task 2 (Reconexão)    →  30 min  — bug crítico de UX
Task 3 (Disconnect)   →  20 min  — depende de Task 2 (compartilha engineRef)
Task 4 (Tab state)    →  30 min  — independente
Task 5 (SFTP)         →  2-3h    — maior complexidade, depende de Task 3 (engineRef)
Task 6 (SQLCipher)    →  45 min  — independente das demais
```

Tasks 1, 4 e 6 são completamente independentes e podem ser feitas em paralelo.
Tasks 2 e 3 devem ser feitas em sequência (3 depende do `engineRef` introduzido em 2).
Task 5 depende do `engineRef` de Task 3.
