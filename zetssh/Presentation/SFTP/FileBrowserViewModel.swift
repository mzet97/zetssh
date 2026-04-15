import Foundation
import AppKit
import Combine

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
