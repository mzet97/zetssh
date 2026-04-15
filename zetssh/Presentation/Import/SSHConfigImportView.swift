import SwiftUI

struct SSHConfigImportView: View {
    @ObservedObject var importVM: SSHConfigImportViewModel
    @ObservedObject var sessionVM: SessionViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Importar SSH Config")
                        .font(.headline)
                    Text("Selecione os hosts que deseja adicionar ao ZetSSH.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // File picker row
            HStack {
                Button("Escolher arquivo…") {
                    importVM.pickFile()
                }
                .controlSize(.regular)

                if !importVM.entries.isEmpty {
                    Text("\(importVM.entries.count) host(s) encontrado(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Selecionar todos") { importVM.selectAll() }
                        .controlSize(.small)
                    Button("Limpar seleção") { importVM.selectNone() }
                        .controlSize(.small)
                } else {
                    Spacer()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Error banner
            if let error = importVM.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
            }

            // Host list
            if importVM.entries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Nenhum arquivo selecionado")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(importVM.entries) { entry in
                    HStack(spacing: 10) {
                        Toggle(
                            isOn: Binding(
                                get: { importVM.selected.contains(entry.alias) },
                                set: { _ in importVM.toggleSelection(alias: entry.alias) }
                            )
                        ) {
                            EmptyView()
                        }
                        .toggleStyle(.checkbox)
                        .labelsHidden()

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.alias)
                                .fontWeight(.medium)
                            Text("\(entry.user)@\(entry.hostname):\(entry.port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let idFile = entry.identityFile {
                                Text(idFile)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }

            Divider()

            // Footer / action row
            HStack {
                Button("Cancelar") {
                    isPresented = false
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button {
                    importVM.importSelected(into: sessionVM)
                    isPresented = false
                } label: {
                    if importVM.isImporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        let count = importVM.selected.count
                        Text(count == 0
                             ? "Importar"
                             : "Importar \(count) \(count == 1 ? "sessão" : "sessões")")
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(importVM.selected.isEmpty || importVM.isImporting)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 480, minHeight: 380)
    }
}
