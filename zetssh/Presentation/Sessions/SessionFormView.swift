import SwiftUI

struct SessionFormView: View {
    @Environment(\.dismiss) var dismiss

    @State private var name:     String = ""
    @State private var host:     String = ""
    @State private var port:     String = "22"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var portError: String?

    var onSave: (Session, String) -> Void

    private var trimmedHost:     String { host.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedUsername: String { username.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var portInt: Int? {
        guard let p = Int(port.trimmingCharacters(in: .whitespaces)),
              (1...65535).contains(p) else { return nil }
        return p
    }
    private var isFormValid: Bool {
        !trimmedHost.isEmpty && !trimmedUsername.isEmpty && portInt != nil
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
                SecureField("Senha", text: $password)
                    .help("Armazenada com segurança no Keychain do macOS")
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
        .frame(minWidth: 420, minHeight: 300)
    }

    private func validatePort() {
        let trimmed = port.trimmingCharacters(in: .whitespaces)
        if let p = Int(trimmed) {
            portError = (1...65535).contains(p) ? nil : "Porta deve estar entre 1 e 65535"
        } else {
            portError = trimmed.isEmpty ? nil : "Porta inválida"
        }
    }

    private func save() {
        guard let portValue = portInt else { return }
        let sessionName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newSession = Session(
            id:       UUID(),
            folderId: nil,
            name:     sessionName.isEmpty ? trimmedHost : sessionName,
            host:     trimmedHost,
            port:     portValue,
            username: trimmedUsername
        )
        onSave(newSession, password)
        dismiss()
    }
}
