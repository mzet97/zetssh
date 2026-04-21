import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum SessionCredentials {
    case password(String)
    case privateKey(path: String, passphrase: String?)
}

private enum AuthMode: String, CaseIterable, Identifiable {
    case password = "Senha"
    case privateKey = "Chave Privada"
    var id: String { rawValue }
}

struct SessionFormView: View {
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = "22"
    @State private var username: String = ""
    @State private var portError: String? = nil
    @State private var authMode: AuthMode = .password
    @State private var password: String = ""
    @State private var keyPath: String = ""
    @State private var passphrase: String = ""
    @State private var saveToKeychain: Bool = true
    @State private var isDragTargeted = false

    private let existingSession: Session?
    var onSave: (Session, SessionCredentials) -> Void

    init(existingSession: Session? = nil, onSave: @escaping (Session, SessionCredentials) -> Void) {
        self.existingSession = existingSession
        self.onSave = onSave
    }

    private var trimmedHost: String { host.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedUsername: String { username.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var portInt: Int? {
        guard let p = Int(port.trimmingCharacters(in: .whitespaces)),
              (1...65535).contains(p) else { return nil }
        return p
    }
    private var isFormValid: Bool {
        guard !trimmedHost.isEmpty, !trimmedUsername.isEmpty, portInt != nil else { return false }
        if authMode == .privateKey { return !keyPath.isEmpty }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            formContent
            footerBar
        }
        .frame(minWidth: 520, minHeight: 480)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(KineticColors.surfaceVariant.opacity(0.7))
                .background(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.6), radius: 20, y: 10)
        .onAppear {
            if let session = existingSession {
                name = session.name
                host = session.host
                port = "\(session.port)"
                username = session.username
                if let key = session.privateKeyPath {
                    authMode = .privateKey
                    keyPath = key
                }
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(KineticColors.macTrafficRed).frame(width: 12, height: 12)
                Circle().fill(KineticColors.macTrafficYellow).frame(width: 12, height: 12)
                Circle().fill(KineticColors.macTrafficGreen).frame(width: 12, height: 12)
            }

            Text("New Connection")
                .font(KineticFont.body.font)
                .fontWeight(.semibold)
                .foregroundStyle(KineticColors.onSurface)
                .padding(.leading, 16)
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
        .background(Color.white.opacity(0.05))
        .overlay(alignment: .bottom) {
            Color.white.opacity(0.05).frame(height: 1)
        }
    }

    private var formContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                formRow(label: "Name") {
                    KineticInputField(placeholder: "e.g. Production Web Server", text: $name)
                }

                formRow(label: "Remote Host") {
                    HStack(spacing: 12) {
                        KineticInputField(placeholder: "hostname or IP address", text: $host)
                            .frame(maxWidth: .infinity)
                        KineticInputField(placeholder: "22", text: $port)
                            .frame(width: 80)
                            .onChange(of: port) { _ in validatePort() }
                    }
                    if let err = portError {
                        Text(err)
                            .font(KineticFont.caption.font)
                            .foregroundStyle(KineticColors.error)
                    }
                }

                formRow(label: "Username") {
                    KineticInputField(placeholder: "username", text: $username)
                }

                formRow(label: "Method") {
                    HStack(spacing: 0) {
                        ForEach(AuthMode.allCases) { mode in
                            Button {
                                authMode = mode
                            } label: {
                                Text(mode == .password ? "Password" : "Key File")
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(authMode == mode ? KineticColors.surfaceContainerHighest : .clear)
                                    )
                                    .foregroundStyle(authMode == mode ? KineticColors.primary : KineticColors.onSurfaceVariant)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(KineticColors.surfaceContainerLowest.opacity(0.4))
                    )
                }

                if authMode == .password {
                    formRow(label: "Password") {
                        KineticInputField(placeholder: "Senha", text: $password, isSecure: true)
                    }
                } else {
                    keyDropZone
                }
            }
            .padding(32)
        }
    }

    private var keyDropZone: some View {
        VStack {
            Spacer().frame(height: 8)
            HStack {
                Spacer().frame(width: 96)
                dropArea
                Spacer()
            }
        }
    }

    private var dropArea: some View {
        VStack(spacing: 12) {
            Image(systemName: "key")
                .font(.system(size: 28))
                .foregroundStyle(KineticColors.primary)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(KineticColors.primary.opacity(0.1))
                )

            Text(keyPath.isEmpty ? "Select Private Key" : URL(fileURLWithPath: keyPath).lastPathComponent)
                .font(KineticFont.body.font)
                .foregroundStyle(KineticColors.onSurface)

            Text("Drop .pem or .pub file here")
                .font(KineticFont.caption.font)
                .foregroundStyle(KineticColors.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .foregroundStyle(
                    isDragTargeted ? KineticColors.primary.opacity(0.4) : KineticColors.outlineVariant.opacity(0.3)
                )
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isDragTargeted ? KineticColors.primary.opacity(0.05) : KineticColors.surfaceContainerLow.opacity(0.3))
        )
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                if let data = data as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    keyPath = url.path
                }
            }
            return true
        }
        .onTapGesture { pickKeyFile() }
    }

    private var footerBar: some View {
        HStack {
            Toggle(isOn: $saveToKeychain) {
                Text("Save to Keychain")
                    .font(.system(size: 11))
                    .foregroundStyle(KineticColors.onSurfaceVariant)
            }
            .toggleStyle(.checkbox)

            Spacer()

            KineticButton("Cancel", style: .ghost) { dismiss() }
                .keyboardShortcut(.cancelAction)

            KineticButton("Connect", style: .primary) { save() }
                .keyboardShortcut(.defaultAction)
                .opacity(isFormValid ? 1 : 0.5)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
        .background(Color.white.opacity(0.05))
    }

    @ViewBuilder
    private func formRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(KineticColors.onSurfaceVariant)
                .frame(width: 80, alignment: .trailing)
                .padding(.top, 8)
            content()
        }
    }

    private func validatePort() {
        let trimmed = port.trimmingCharacters(in: .whitespaces)
        if let p = Int(trimmed) {
            portError = (1...65535).contains(p) ? nil : "Porta deve estar entre 1 e 65535"
        } else {
            portError = trimmed.isEmpty ? nil : "Porta inválida"
        }
    }

    private func pickKeyFile() {
        let panel = NSOpenPanel()
        panel.title = "Select SSH Private Key"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if let sshDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true) as URL?,
           FileManager.default.fileExists(atPath: sshDir.path) {
            panel.directoryURL = sshDir
        }
        if panel.runModal() == .OK, let url = panel.url {
            keyPath = url.path
        }
    }

    private func save() {
        guard let portValue = portInt else { return }
        let sessionName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionId = existingSession?.id ?? UUID()
        let newSession = Session(
            id: sessionId,
            folderId: existingSession?.folderId,
            name: sessionName.isEmpty ? trimmedHost : sessionName,
            host: trimmedHost,
            port: portValue,
            username: trimmedUsername,
            privateKeyPath: authMode == .privateKey ? keyPath : nil,
            isFavorite: existingSession?.isFavorite ?? false
        )

        let credentials: SessionCredentials
        switch authMode {
        case .password:
            credentials = .password(password)
        case .privateKey:
            credentials = .privateKey(
                path: keyPath,
                passphrase: passphrase.isEmpty ? nil : passphrase
            )
        }

        onSave(newSession, credentials)
        dismiss()
    }
}
