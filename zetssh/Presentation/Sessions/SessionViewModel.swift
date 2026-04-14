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

    func save(_ session: Session, password: String) {
        var s = session
        do {
            try AppDatabase.shared.dbWriter.write { db in try s.save(db) }
            if !password.isEmpty {
                try KeychainService.shared.save(password: password, forSessionId: s.id)
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
