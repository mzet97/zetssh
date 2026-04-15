import Foundation
import GRDB
import Combine

@MainActor
final class SessionViewModel: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published var errorMessage: String?

    private var observation: AnyDatabaseCancellable?

    init() {
        startObserving()
    }

    private func startObserving() {
        let observation = ValueObservation.tracking { db in
            try Session.fetchAll(db)
        }
        self.observation = observation.start(
            in: AppDatabase.shared.dbWriter,
            scheduling: .immediate,
            onError: { [weak self] error in
                self?.errorMessage = "Erro ao carregar sessões: \(error.localizedDescription)"
            },
            onChange: { [weak self] sessions in
                self?.sessions = sessions
            }
        )
    }

    func save(_ session: Session, credentials: SessionCredentials) {
        var s = session
        do {
            try AppDatabase.shared.dbWriter.write { db in try s.save(db) }
            switch credentials {
            case .password(let pw):
                if !pw.isEmpty {
                    try KeychainService.shared.save(password: pw, forSessionId: s.id)
                }
                try KeychainService.shared.deletePassphrase(forSessionId: s.id)
            case .privateKey(_, let passphrase):
                try KeychainService.shared.deletePassword(forSessionId: s.id)
                if let pp = passphrase {
                    try KeychainService.shared.savePassphrase(pp, forSessionId: s.id)
                } else {
                    try KeychainService.shared.deletePassphrase(forSessionId: s.id)
                }
            }
        } catch {
            errorMessage = "Erro ao salvar sessão: \(error.localizedDescription)"
        }
    }

    func delete(_ session: Session) {
        do {
            try AppDatabase.shared.dbWriter.write { db in try session.delete(db) }
            try KeychainService.shared.deletePassword(forSessionId: session.id)
        } catch {
            errorMessage = "Erro ao deletar sessão: \(error.localizedDescription)"
        }
    }
}
