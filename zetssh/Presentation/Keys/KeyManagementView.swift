import SwiftUI
import GRDB

struct KeyManagementView: View {
    @ObservedObject var viewModel: SessionViewModel

    @State private var selectedKeyId: String?
    @State private var searchText = ""
    @State private var showRemoveKeyConfirmation = false

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
        .alert("Remove SSH Key", isPresented: $showRemoveKeyConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                if let entry = keyEntries.first(where: { $0.id == selectedKeyId }) {
                    removeKey(entry)
                }
            }
        } message: {
            Text("This will remove the key reference from ZetSSH. The key file on disk will not be deleted.")
        }
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
                .help("Generate new SSH key pair")
                .onTapGesture { generateKeyPair() }
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
                        KineticButton("Copy Public Key", icon: "doc.on.doc", style: .ghost) { copyPublicKey(entry) }
                        KineticButton("Remove", icon: "trash", style: .destructive) { showRemoveKeyConfirmation = true }
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

    private func copyPublicKey(_ entry: KeyEntry) {
        let pubKeyPath = entry.path + ".pub"
        let fm = FileManager.default
        guard fm.fileExists(atPath: pubKeyPath),
              let contents = try? String(contentsOfFile: pubKeyPath, encoding: .utf8) else {
            let alert = NSAlert()
            alert.messageText = "Public key not found"
            alert.informativeText = "No .pub file found at:\n\(pubKeyPath)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(contents.trimmingCharacters(in: .whitespacesAndNewlines), forType: .string)
    }

    private func removeKey(_ entry: KeyEntry) {
        let sessionsUsingKey = viewModel.sessions.filter { $0.privateKeyPath == entry.path }
        for session in sessionsUsingKey {
            var updated = session
            updated.privateKeyPath = nil
            do {
                try AppDatabase.shared.dbWriter.write { db in try updated.save(db) }
            } catch {
                viewModel.errorMessage = "Error updating session: \(error.localizedDescription)"
            }
        }
        selectedKeyId = nil
    }

    private func generateKeyPair() {
        let alert = NSAlert()
        alert.messageText = "Generate New SSH Key Pair"
        alert.informativeText = "Choose the key type to generate:"
        alert.alertStyle = .informational

        let menu = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        menu.addItems(withTitles: ["Ed25519 (Recommended)", "RSA 4096", "ECDSA 256"])
        alert.accessoryView = menu

        alert.addButton(withTitle: "Generate")
        alert.addButton(withTitle: "Cancel")

        guard let window = NSApp.keyWindow else { return }
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }

            let keyType = menu.titleOfSelectedItem ?? "Ed25519 (Recommended)"
            let typeArg: String
            switch keyType {
            case let t where t.hasPrefix("RSA"): typeArg = "rsa"
            case let t where t.hasPrefix("ECDSA"): typeArg = "ecdsa"
            default: typeArg = "ed25519"
            }

            let sshDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ssh", isDirectory: true).path
            let filename = "zetssh_key_\(typeArg)_\(Int(Date().timeIntervalSince1970))"
            let keyPath = "\(sshDir)/\(filename)"

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
            task.arguments = ["-t", typeArg, "-f", keyPath, "-N", "", "-C", "zetssh@\(Date())"]

            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus == 0 {
                    let message = NSAlert()
                    message.messageText = "Key Generated"
                    message.informativeText = "Saved to:\n\(keyPath)\n\nYou can now assign it to sessions."
                    message.alertStyle = .informational
                    message.addButton(withTitle: "OK")
                    message.runModal()
                } else {
                    viewModel.errorMessage = "ssh-keygen failed with exit code \(task.terminationStatus)"
                }
            } catch {
                viewModel.errorMessage = "Failed to run ssh-keygen: \(error.localizedDescription)"
            }
        }
    }
}
