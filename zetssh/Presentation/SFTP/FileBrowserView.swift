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
