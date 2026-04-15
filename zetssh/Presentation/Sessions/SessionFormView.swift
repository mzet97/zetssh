import SwiftUI
import AppKit

// MARK: - Credential payload

enum SessionCredentials {
    case password(String)
    case privateKey(path: String, passphrase: String?)
}

// MARK: - Auth mode

private enum AuthMode: String, CaseIterable, Identifiable {
    case password    = "Senha"
    case privateKey  = "Chave Privada"
    var id: String { rawValue }
}

// MARK: - SessionFormView

struct SessionFormView: View {
    @Environment(\.dismiss) var dismiss

    @State private var name:        String   = ""
    @State private var host:        String   = ""
    @State private var port:        String   = "22"
    @State private var username:    String   = ""
    @State private var portError:   String?  = nil
    @State private var authMode:    AuthMode = .password

    // Password branch
    @State private var password:    String = ""

    // Private key branch
    @State private var keyPath:     String = ""
    @State private var passphrase:  String = ""

    var onSave: (Session, SessionCredentials) -> Void

    private var trimmedHost:     String { host.trimmingCharacters(in: .whitespacesAndNewlines) }
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
        Form {
            Section(header: Text("Geral").font(.headline)) {
                TextField("Nome (ex: Prod Server)", text: $name)
                TextField("Host / IP (obrigatório)", text: $host)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Porta", text: $port)
                        .onChange(of: port) { _ in validatePort() }
                    if let err = portError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }
            }

            Section(header: Text("Credenciais").font(.headline)) {
                TextField("Usuário (obrigatório)", text: $username)

                Picker("Autenticação", selection: $authMode) {
                    ForEach(AuthMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if authMode == .password {
                    SecureField("Senha", text: $password)
                        .help("Armazenada com segurança no Keychain do macOS")
                } else {
                    keyPickerRow
                    SecureField("Frase-senha (opcional)", text: $passphrase)
                        .help("Deixe em branco se a chave não tem frase-senha")
                }
            }

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Salvar") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isFormValid)
            }
            .padding(.top)
        }
        .padding(24)
        .frame(minWidth: 460, minHeight: 340)
    }

    // MARK: - Private key picker row

    private var keyPickerRow: some View {
        HStack {
            Text(keyPath.isEmpty ? "Nenhuma chave selecionada" : keyPath)
                .foregroundStyle(keyPath.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Escolher…") { pickKeyFile() }
        }
    }

    // MARK: - Helpers

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
        panel.title = "Selecionar chave privada SSH"
        panel.message = "Escolha um arquivo de chave privada (PEM ou OpenSSH)"
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
        let newSession = Session(
            id:             UUID(),
            folderId:       nil,
            name:           sessionName.isEmpty ? trimmedHost : sessionName,
            host:           trimmedHost,
            port:           portValue,
            username:       trimmedUsername,
            privateKeyPath: authMode == .privateKey ? keyPath : nil
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
