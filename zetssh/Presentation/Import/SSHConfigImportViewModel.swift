import AppKit
import Combine
import Foundation

@MainActor
final class SSHConfigImportViewModel: ObservableObject {
    // MARK: - Published state

    @Published var entries: [SSHConfigEntry] = []
    @Published var selected: Set<String> = []
    @Published var errorMessage: String?
    @Published var isImporting: Bool = false

    // MARK: - File picking (sandbox-safe)

    func pickFile() {
        let panel = NSOpenPanel()
        panel.title = "Selecionar SSH Config"
        panel.message = "Escolha o arquivo de configuração SSH a importar."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        let suggestedDir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh")
        panel.directoryURL = suggestedDir
        panel.nameFieldStringValue = "config"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFile(url: url)
    }

    // MARK: - Loading

    private func loadFile(url: URL) {
        let parsed = SSHConfigParser.parse(url: url)
        if parsed.isEmpty {
            errorMessage = "Nenhum host encontrado em \(url.lastPathComponent). Verifique se o arquivo está no formato OpenSSH."
        } else {
            errorMessage = nil
        }
        entries = parsed
        selected = Set(parsed.map(\.alias))
    }

    // MARK: - Import

    func importSelected(into sessionViewModel: SessionViewModel) {
        isImporting = true
        defer { isImporting = false }

        let toImport = entries.filter { selected.contains($0.alias) }

        for entry in toImport {
            var session = Session(
                id: UUID(),
                folderId: nil,
                name: entry.alias,
                host: entry.hostname,
                port: entry.port,
                username: entry.user
            )
            session.privateKeyPath = entry.identityFile

            let credentials: SessionCredentials
            if let keyPath = entry.identityFile {
                credentials = .privateKey(path: keyPath, passphrase: nil)
            } else {
                credentials = .password("")
            }
            sessionViewModel.save(session, credentials: credentials)
        }
    }

    // MARK: - Helpers

    func toggleSelection(alias: String) {
        if selected.contains(alias) {
            selected.remove(alias)
        } else {
            selected.insert(alias)
        }
    }

    func selectAll() {
        selected = Set(entries.map(\.alias))
    }

    func selectNone() {
        selected.removeAll()
    }
}
