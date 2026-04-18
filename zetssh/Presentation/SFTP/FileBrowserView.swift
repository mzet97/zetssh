import SwiftUI
import AppKit

struct FileBrowserView: View {
    @ObservedObject var viewModel: FileBrowserViewModel
    @Environment(\.dismiss) var dismiss
    var engine: RealSSHEngine?

    @State private var showingNewFolderDialog = false
    @State private var newFolderName = ""

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

                Button { viewModel.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }

                Button { viewModel.copyPathToClipboard() } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copiar caminho")

                Button { showingNewFolderDialog = true } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Nova pasta")

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
                        if item.isDirectory {
                            Button("Open") { viewModel.navigate(to: item) }
                        } else {
                            Button("Download") { viewModel.download(item: item) }
                        }
                        Button("Copy Path") {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(item.path, forType: .string)
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
        .alert("Nova Pasta", isPresented: $showingNewFolderDialog) {
            TextField("Nome da pasta", text: $newFolderName)
            Button("Criar") {
                let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    viewModel.createDirectory(name: name)
                }
                newFolderName = ""
            }
            Button("Cancelar", role: .cancel) {
                newFolderName = ""
            }
        } message: {
            Text("Criar nova pasta em \(viewModel.currentPath)")
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
        .onAppear {
            if let engine {
                Task { await viewModel.connectSFTP(engine: engine) }
            } else {
                viewModel.loadDirectory()
            }
        }
    }
}
