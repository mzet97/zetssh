import SwiftUI

struct KeyManagementView: View {
    @ObservedObject var viewModel: SessionViewModel

    @State private var selectedKeyId: String?
    @State private var searchText = ""

    private struct KeyEntry: Identifiable {
        let id: String
        let name: String
        let path: String
        let type: String
        let sessions: [Session]
    }

    private var keyEntries: [KeyEntry] {
        let keysWithPath = viewModel.sessions.compactMap { session -> KeyEntry? in
            guard let path = session.privateKeyPath, !path.isEmpty else { return nil }
            let filename = URL(fileURLWithPath: path).lastPathComponent
            return KeyEntry(
                id: path,
                name: filename,
                path: path,
                type: filename.contains("ed25519") ? "Ed25519" : filename.contains("ecdsa") ? "ECDSA" : "RSA",
                sessions: viewModel.sessions.filter { $0.privateKeyPath == path }
            )
        }
        let unique = Dictionary(grouping: keysWithPath, by: \.id).values.compactMap { $0.first }
        if searchText.isEmpty { return unique }
        return unique.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.type.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        HStack(spacing: 0) {
            keyList
            GhostDivider(vertical: true)
            keyDetail
        }
        .background(KineticColors.surfaceContainer)
    }

    private var keyList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SSH Keys")
                    .font(KineticFont.headline.font)
                    .foregroundStyle(KineticColors.onSurface)
                Spacer()
                Button {
                    importKey()
                } label: {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(KineticColors.onSurfaceVariant)
                }
                .buttonStyle(.plain)
                Button {} label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                        .foregroundStyle(KineticColors.onSurfaceVariant)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(KineticColors.onSurfaceVariant)
                TextField("Search keys…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(KineticFont.caption.font)
                    .foregroundStyle(KineticColors.onSurface)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(KineticColors.surfaceContainerHighest)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 4) {
                    if keyEntries.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "key")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(KineticColors.outline)
                            Text("No SSH keys found")
                                .font(KineticFont.caption.font)
                                .foregroundStyle(KineticColors.onSurfaceVariant)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                    ForEach(keyEntries) { entry in
                        keyListRow(entry)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(width: 260)
        .background(KineticColors.surfaceContainerLow)
    }

    @ViewBuilder
    private func keyListRow(_ entry: KeyEntry) -> some View {
        let isSelected = selectedKeyId == entry.id

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? KineticColors.primary : KineticColors.onSurface)
                    .lineLimit(1)
                Spacer()
                Text(entry.type)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(KineticColors.outlineVariant)
                    .tracking(0.5)
            }
            Text(entry.path)
                .font(.system(size: 11))
                .foregroundStyle(KineticColors.onSurfaceVariant)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? KineticColors.surfaceContainer : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedKeyId = entry.id
        }
    }

    @ViewBuilder
    private var keyDetail: some View {
        if let entry = keyEntries.first(where: { $0.id == selectedKeyId }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 10) {
                                Image(systemName: "key")
                                    .font(.system(size: 24))
                                    .foregroundStyle(KineticColors.primary)
                                Text(entry.name)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(KineticColors.onSurface)
                            }
                            Text("Path: \(entry.path)")
                                .font(.system(size: 13))
                                .foregroundStyle(KineticColors.onSurfaceVariant)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        KineticButton("Copy Public Key", icon: "doc.on.doc", style: .ghost) {}
                        KineticButton("Remove", icon: "trash", style: .destructive) {}
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("KEY TYPE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(KineticColors.outline)
                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Algorithm")
                                    .font(.system(size: 11))
                                    .foregroundStyle(KineticColors.onSurfaceVariant)
                                Text(entry.type)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(KineticColors.onSurface)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Used by")
                                    .font(.system(size: 11))
                                    .foregroundStyle(KineticColors.onSurfaceVariant)
                                Text("\(entry.sessions.count) server\(entry.sessions.count == 1 ? "" : "s")")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(KineticColors.onSurface)
                            }
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(KineticColors.surfaceContainerLow)
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("PUBLIC KEY PREVIEW")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(KineticColors.outline)
                        Text("Key file stored at:\n\(entry.path)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(KineticColors.onSurfaceVariant)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(KineticColors.surfaceContainerLowest)
                            )
                    }
                }
                .padding(32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KineticColors.surfaceContainer)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "key")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(KineticColors.outline)
                Text("Select a key to view details")
                    .font(KineticFont.body.font)
                    .foregroundStyle(KineticColors.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KineticColors.surfaceContainer)
        }
    }

    private func importKey() {
        let panel = NSOpenPanel()
        panel.title = "Import SSH Key"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if let sshDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true) as URL?,
           FileManager.default.fileExists(atPath: sshDir.path) {
            panel.directoryURL = sshDir
        }
        panel.runModal()
    }
}
