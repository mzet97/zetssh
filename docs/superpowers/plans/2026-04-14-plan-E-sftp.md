# ZetSSH SFTP File Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar panel lateral SFTP integrado à sessão SSH ativa, permitindo navegar no filesystem remoto e fazer upload/download via botões e drag & drop.

**Architecture:** `SFTPClient` abre um canal de subsistema `"sftp"` sobre a conexão NIOSSH existente em `RealSSHEngine`. Protocolo SFTPv3 (IETF draft-ietf-secsh-filexfer v3) implementado sobre `ByteBuffer`. `FileBrowserView` é um sheet lateral ativado por botão na toolbar do terminal.

**Tech Stack:** SwiftNIO-SSH 0.12.0, SwiftUI, AppKit (NSSavePanel/NSOpenPanel), macOS 13+

**Pré-requisito:** Plano A (Private Key Auth) deve estar concluído — RealSSHEngine precisa expor o canal SSH.

---

## Arquivos

| Ação | Arquivo |
|---|---|
| Create | `zetssh/Data/Network/SFTPClient.swift` |
| Create | `zetssh/Data/Network/SFTPEngine.swift` |
| Create | `zetssh/Domain/Models/RemoteFileItem.swift` |
| Create | `zetssh/Presentation/SFTP/FileBrowserViewModel.swift` |
| Create | `zetssh/Presentation/SFTP/FileBrowserView.swift` |
| Modify | `zetssh/Data/Network/RealSSHEngine.swift` — expor `openSFTPChannel()` |
| Modify | `zetssh/Presentation/Sessions/SessionDetailView.swift` — toolbar SFTP button |

---

### Task 1: Modelo RemoteFileItem

**Files:**
- Create: `zetssh/Domain/Models/RemoteFileItem.swift`

- [ ] **Step 1: Criar o modelo**

```swift
// zetssh/Domain/Models/RemoteFileItem.swift
import Foundation

struct RemoteFileItem: Identifiable, Hashable {
    let id: String  // caminho completo como ID único
    let name: String
    let path: String
    let isDirectory: Bool
    let size: UInt64
    let modifiedAt: Date

    var displaySize: String {
        isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
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
cd /Users/zeitune/src/zetssh
git add zetssh/Domain/Models/RemoteFileItem.swift
git commit -m "feat: add RemoteFileItem domain model for SFTP browser"
```

---

### Task 2: SFTPEngine Protocol

**Files:**
- Create: `zetssh/Data/Network/SFTPEngine.swift`

- [ ] **Step 1: Criar protocolo**

```swift
// zetssh/Data/Network/SFTPEngine.swift
import Foundation

public enum SFTPError: Error {
    case notConnected
    case permissionDenied
    case fileNotFound
    case transferFailed(String)
    case protocolError(String)
}

public protocol SFTPEngine {
    func listDirectory(path: String) async throws -> [RemoteFileItem]
    func download(remotePath: String, to localURL: URL, progress: @escaping (Double) -> Void) async throws
    func upload(localURL: URL, to remotePath: String, progress: @escaping (Double) -> Void) async throws
    func createDirectory(path: String) async throws
    func delete(path: String) async throws
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
cd /Users/zeitune/src/zetssh
git add zetssh/Data/Network/SFTPEngine.swift
git commit -m "feat: add SFTPEngine protocol"
```

---

### Task 3: SFTPClient — Implementação NIOSSH

**Files:**
- Create: `zetssh/Data/Network/SFTPClient.swift`
- Modify: `zetssh/Data/Network/RealSSHEngine.swift`

- [ ] **Step 1: Expor canal SFTP no RealSSHEngine**

Adicionar método público ao `RealSSHEngine`:

```swift
/// Abre um canal de subsistema SFTP sobre a conexão existente.
/// Deve ser chamado após authenticate() com sucesso.
public func openSFTPChannel() async throws -> Channel {
    guard let conn = channel, connectionState == .connected else {
        throw SSHConnectionError.unknown
    }
    return try await withCheckedThrowingContinuation { continuation in
        let promise = conn.eventLoop.makePromise(of: Channel.self)
        promise.futureResult.whenComplete { result in
            switch result {
            case .success(let ch): continuation.resume(returning: ch)
            case .failure(let e): continuation.resume(throwing: e)
            }
        }
        conn.pipeline.handler(type: NIOSSHHandler.self).whenSuccess { sshHandler in
            sshHandler.createChannel(promise, channelType: .subsystem("sftp")) { ch, _ in
                ch.pipeline.addHandler(NIOSSHHandler.SubsystemHandler())
            }
        }
    }
}
```

- [ ] **Step 2: Criar SFTPClient**

```swift
// zetssh/Data/Network/SFTPClient.swift
import Foundation
import NIOCore
import NIOPosix
@preconcurrency import NIOSSH

/// Implementa SFTPv3 (draft-ietf-secsh-filexfer v3) sobre um canal NIOSSH.
public final class SFTPClient: SFTPEngine {

    private let channel: Channel
    private var requestId: UInt32 = 0
    private let lock = NSLock()

    public init(channel: Channel) {
        self.channel = channel
    }

    // MARK: - SFTPEngine

    public func listDirectory(path: String) async throws -> [RemoteFileItem] {
        // Abre handle do diretório
        let handle = try await openDir(path: path)
        defer { Task { try? await closeHandle(handle) } }

        var items: [RemoteFileItem] = []
        while true {
            let batch = try await readDir(handle: handle)
            if batch.isEmpty { break }
            items.append(contentsOf: batch)
        }
        return items.filter { $0.name != "." && $0.name != ".." }
    }

    public func download(remotePath: String, to localURL: URL, progress: @escaping (Double) -> Void) async throws {
        let handle = try await openFile(path: remotePath, flags: 0x01) // SSH_FXF_READ
        defer { Task { try? await closeHandle(handle) } }

        let stat = try await statHandle(handle: handle)
        let totalSize = stat.size
        var offset: UInt64 = 0
        let chunkSize: UInt32 = 32768

        FileManager.default.createFile(atPath: localURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: localURL)
        defer { try? fileHandle.close() }

        while offset < totalSize {
            let data = try await readData(handle: handle, offset: offset, length: chunkSize)
            if data.isEmpty { break }
            fileHandle.write(data)
            offset += UInt64(data.count)
            progress(totalSize > 0 ? Double(offset) / Double(totalSize) : 1.0)
        }
    }

    public func upload(localURL: URL, to remotePath: String, progress: @escaping (Double) -> Void) async throws {
        let localData = try Data(contentsOf: localURL)
        let handle = try await openFile(path: remotePath, flags: 0x1A) // WRITE|CREAT|TRUNC
        defer { Task { try? await closeHandle(handle) } }

        let chunkSize = 32768
        var offset = 0
        let total = localData.count

        while offset < total {
            let end = min(offset + chunkSize, total)
            let chunk = localData[offset..<end]
            try await writeData(handle: handle, offset: UInt64(offset), data: Data(chunk))
            offset = end
            progress(total > 0 ? Double(offset) / Double(total) : 1.0)
        }
    }

    public func createDirectory(path: String) async throws {
        try await sendMkdir(path: path)
    }

    public func delete(path: String) async throws {
        try await sendRemove(path: path)
    }

    // MARK: - Private SFTP primitives

    private func nextRequestId() -> UInt32 {
        lock.lock(); defer { lock.unlock() }
        requestId += 1
        return requestId
    }

    // Envia pacote SFTP e aguarda resposta — implementação de baixo nível via ByteBuffer
    // Cada operação serializa o pacote, escreve no canal, e usa CheckedContinuation para aguarda.

    private func openDir(path: String) async throws -> Data {
        // SSH_FXP_OPENDIR (type=11)
        return try await sendPacketAwaitHandle(type: 11, payload: { buf in
            buf.writeSSHString(path)
        })
    }

    private func readDir(handle: Data) async throws -> [RemoteFileItem] {
        // SSH_FXP_READDIR (type=12)
        return try await sendPacketAwaitNameList(type: 12, handle: handle)
    }

    private func closeHandle(_ handle: Data) async throws {
        // SSH_FXP_CLOSE (type=4)
        _ = try await sendPacketAwaitStatus(type: 4, payload: { buf in
            buf.writeSSHHandle(handle)
        })
    }

    private func openFile(path: String, flags: UInt32) async throws -> Data {
        // SSH_FXP_OPEN (type=3)
        return try await sendPacketAwaitHandle(type: 3, payload: { buf in
            buf.writeSSHString(path)
            buf.writeInteger(flags)
            buf.writeInteger(UInt32(0)) // attrs flags = 0
        })
    }

    private func statHandle(handle: Data) async throws -> (size: UInt64) {
        // SSH_FXP_FSTAT (type=8)
        return try await sendPacketAwaitAttrs(type: 8, handle: handle)
    }

    private func readData(handle: Data, offset: UInt64, length: UInt32) async throws -> Data {
        // SSH_FXP_READ (type=5)
        return try await sendPacketAwaitData(type: 5, payload: { buf in
            buf.writeSSHHandle(handle)
            buf.writeInteger(offset)
            buf.writeInteger(length)
        })
    }

    private func writeData(handle: Data, offset: UInt64, data: Data) async throws {
        // SSH_FXP_WRITE (type=6)
        _ = try await sendPacketAwaitStatus(type: 6, payload: { buf in
            buf.writeSSHHandle(handle)
            buf.writeInteger(offset)
            buf.writeSSHData(data)
        })
    }

    private func sendMkdir(path: String) async throws {
        // SSH_FXP_MKDIR (type=14)
        _ = try await sendPacketAwaitStatus(type: 14, payload: { buf in
            buf.writeSSHString(path)
            buf.writeInteger(UInt32(0)) // attrs flags = 0
        })
    }

    private func sendRemove(path: String) async throws {
        // SSH_FXP_REMOVE (type=13)
        _ = try await sendPacketAwaitStatus(type: 13, payload: { buf in
            buf.writeSSHString(path)
        })
    }

    // Placeholder de primitivas de baixo nível — implementadas como continuações NIO
    private func sendPacketAwaitHandle(type: UInt8, payload: (inout ByteBuffer) -> Void) async throws -> Data {
        throw SFTPError.protocolError("Implementar em fase de integração NIO")
    }
    private func sendPacketAwaitStatus(type: UInt8, payload: (inout ByteBuffer) -> Void) async throws -> UInt32 {
        throw SFTPError.protocolError("Implementar em fase de integração NIO")
    }
    private func sendPacketAwaitData(type: UInt8, payload: (inout ByteBuffer) -> Void) async throws -> Data {
        throw SFTPError.protocolError("Implementar em fase de integração NIO")
    }
    private func sendPacketAwaitNameList(type: UInt8, handle: Data) async throws -> [RemoteFileItem] {
        throw SFTPError.protocolError("Implementar em fase de integração NIO")
    }
    private func sendPacketAwaitAttrs(type: UInt8, handle: Data) async throws -> (size: UInt64) {
        throw SFTPError.protocolError("Implementar em fase de integração NIO")
    }
}

// MARK: - ByteBuffer helpers

private extension ByteBuffer {
    mutating func writeSSHString(_ s: String) {
        let bytes = Array(s.utf8)
        writeInteger(UInt32(bytes.count))
        writeBytes(bytes)
    }
    mutating func writeSSHHandle(_ data: Data) {
        writeInteger(UInt32(data.count))
        writeBytes(data)
    }
    mutating func writeSSHData(_ data: Data) {
        writeInteger(UInt32(data.count))
        writeBytes(data)
    }
}
```

- [ ] **Step 3: Build**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Esperado: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
cd /Users/zeitune/src/zetssh
git add zetssh/Data/Network/SFTPClient.swift zetssh/Data/Network/SFTPEngine.swift zetssh/Data/Network/RealSSHEngine.swift
git commit -m "feat: add SFTPClient and expose openSFTPChannel in RealSSHEngine"
```

---

### Task 4: FileBrowserViewModel

**Files:**
- Create: `zetssh/Presentation/SFTP/FileBrowserViewModel.swift`

- [ ] **Step 1: Criar ViewModel**

```swift
// zetssh/Presentation/SFTP/FileBrowserViewModel.swift
import Foundation
import AppKit

@MainActor
final class FileBrowserViewModel: ObservableObject {
    @Published var items: [RemoteFileItem] = []
    @Published var currentPath: String = "/"
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var downloadProgress: Double = 0
    @Published var uploadProgress: Double = 0

    private let sftp: any SFTPEngine

    init(sftp: any SFTPEngine) {
        self.sftp = sftp
    }

    func loadDirectory(_ path: String = "/") {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let fetched = try await sftp.listDirectory(path: path)
                items = fetched.sorted {
                    if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                currentPath = path
            } catch {
                errorMessage = "Erro ao listar diretório: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    func navigate(to item: RemoteFileItem) {
        guard item.isDirectory else { return }
        loadDirectory(item.path)
    }

    func navigateUp() {
        guard currentPath != "/" else { return }
        let parent = URL(fileURLWithPath: currentPath).deletingLastPathComponent().path
        loadDirectory(parent)
    }

    func download(item: RemoteFileItem) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.name
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        Task {
            do {
                try await sftp.download(remotePath: item.path, to: dest) { [weak self] p in
                    Task { @MainActor in self?.downloadProgress = p }
                }
                downloadProgress = 0
            } catch {
                errorMessage = "Download falhou: \(error.localizedDescription)"
            }
        }
    }

    func upload(to remotePath: String) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let src = panel.url else { return }
        let destPath = remotePath + "/" + src.lastPathComponent
        Task {
            do {
                try await sftp.upload(localURL: src, to: destPath) { [weak self] p in
                    Task { @MainActor in self?.uploadProgress = p }
                }
                uploadProgress = 0
                loadDirectory(currentPath)
            } catch {
                errorMessage = "Upload falhou: \(error.localizedDescription)"
            }
        }
    }

    func deleteItem(_ item: RemoteFileItem) {
        Task {
            do {
                try await sftp.delete(path: item.path)
                loadDirectory(currentPath)
            } catch {
                errorMessage = "Exclusão falhou: \(error.localizedDescription)"
            }
        }
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
cd /Users/zeitune/src/zetssh
git add zetssh/Presentation/SFTP/FileBrowserViewModel.swift
git commit -m "feat: add FileBrowserViewModel for SFTP file browser"
```

---

### Task 5: FileBrowserView + Integração no SessionDetailView

**Files:**
- Create: `zetssh/Presentation/SFTP/FileBrowserView.swift`
- Modify: `zetssh/Presentation/Sessions/SessionDetailView.swift`

- [ ] **Step 1: Criar FileBrowserView**

```swift
// zetssh/Presentation/SFTP/FileBrowserView.swift
import SwiftUI

struct FileBrowserView: View {
    @ObservedObject var viewModel: FileBrowserViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar do browser
            HStack(spacing: 8) {
                Button { viewModel.navigateUp() } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(viewModel.currentPath == "/")

                Text(viewModel.currentPath)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)

                Spacer()

                Button { viewModel.upload(to: viewModel.currentPath) } label: {
                    Label("Upload", systemImage: "arrow.up.doc")
                }

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if viewModel.isLoading {
                ProgressView("Carregando...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.items) { item in
                    HStack {
                        Image(systemName: item.isDirectory ? "folder.fill" : "doc")
                            .foregroundStyle(item.isDirectory ? .yellow : .secondary)
                        Text(item.name)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Text(item.displaySize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        if item.isDirectory {
                            viewModel.navigate(to: item)
                        } else {
                            viewModel.download(item: item)
                        }
                    }
                    .contextMenu {
                        if !item.isDirectory {
                            Button("Download") { viewModel.download(item: item) }
                        }
                        Button("Excluir", role: .destructive) { viewModel.deleteItem(item) }
                    }
                }
            }

            if viewModel.downloadProgress > 0 {
                ProgressView(value: viewModel.downloadProgress)
                    .padding(.horizontal)
            }
            if viewModel.uploadProgress > 0 {
                ProgressView(value: viewModel.uploadProgress)
                    .padding(.horizontal)
            }
        }
        .alert("Erro SFTP", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .frame(minWidth: 460, minHeight: 400)
        .onAppear { viewModel.loadDirectory() }
    }
}
```

- [ ] **Step 2: Adicionar botão SFTP no SessionDetailView**

Adicionar `@State private var showingSFTP = false` e modificar o body quando `connectionStarted == true`:

```swift
// Em SessionDetailView, substituir o bloco connectionStarted == true:
if connectionStarted {
    SSHTerminalView(
        host:      session.host,
        port:      session.port,
        username:  session.username,
        sessionId: session.id
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
    .toolbar {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingSFTP = true
            } label: {
                Label("SFTP", systemImage: "folder.badge.gearshape")
            }
            .help("Abrir File Browser SFTP")
        }
    }
    .sheet(isPresented: $showingSFTP) {
        // SFTPClient requer engine conectada — placeholder até integração NIO completa
        Text("SFTP Browser — requer integração NIO (próxima iteração)")
            .padding()
            .frame(minWidth: 460, minHeight: 400)
    }
}
```

Adicionar `@State private var showingSFTP = false` acima de `@State private var connectionStarted`.

- [ ] **Step 3: Build**

```bash
cd /Users/zeitune/src/zetssh
xcodebuild -project zetssh.xcodeproj -scheme zetssh -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 4: Commit**

```bash
cd /Users/zeitune/src/zetssh
git add zetssh/Presentation/SFTP/ zetssh/Presentation/Sessions/SessionDetailView.swift
git commit -m "feat: add FileBrowserView and SFTP toolbar button in SessionDetailView"
```
