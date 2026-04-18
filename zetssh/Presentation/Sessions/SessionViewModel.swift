import Foundation
import GRDB
import Combine

@MainActor
final class SessionViewModel: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var historyEntries: [SessionHistory] = []
    @Published var errorMessage: String?

    private var observation: AnyDatabaseCancellable?
    private var historyObservation: AnyDatabaseCancellable?
    private var activeHistoryId: UUID?

    init() {
        startObserving()
        startObservingHistory()
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

    private func startObservingHistory() {
        let obs = ValueObservation.tracking { db in
            try SessionHistory
                .order(Column("connectedAt").desc)
                .fetchAll(db)
        }
        historyObservation = obs.start(
            in: AppDatabase.shared.dbWriter,
            scheduling: .immediate,
            onError: { _ in },
            onChange: { [weak self] entries in
                self?.historyEntries = Array(entries.prefix(100))
            }
        )
    }

    func recordConnectionStarted(session: Session) {
        let entry = SessionHistory(
            id: UUID(),
            sessionId: session.id,
            sessionName: session.name,
            host: session.host,
            username: session.username,
            port: session.port,
            connectedAt: Date(),
            disconnectedAt: nil,
            duration: nil
        )
        do {
            try AppDatabase.shared.dbWriter.write { db in try entry.save(db) }
            activeHistoryId = entry.id
        } catch {
            errorMessage = "Erro ao registrar histórico: \(error.localizedDescription)"
        }
    }

    func recordConnectionEnded() {
        guard let historyId = activeHistoryId else { return }
        do {
            try AppDatabase.shared.dbWriter.write { db in
                guard var entry = try SessionHistory.fetchOne(db, key: historyId) else { return }
                let now = Date()
                entry.disconnectedAt = now
                entry.duration = now.timeIntervalSince(entry.connectedAt)
                try entry.save(db)
            }
            activeHistoryId = nil
        } catch {
            errorMessage = "Erro ao finalizar histórico: \(error.localizedDescription)"
        }
    }

    func save(_ session: Session, credentials: SessionCredentials) {
        var s = session
        do {
            try AppDatabase.shared.dbWriter.write { db in try s.save(db) }
            switch credentials {
            case .password(let pw):
                try KeychainService.shared.save(password: pw, forSessionId: s.id)
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
            try KeychainService.shared.deletePassphrase(forSessionId: session.id)
        } catch {
            errorMessage = "Erro ao deletar sessão: \(error.localizedDescription)"
        }
    }

    func toggleFavorite(_ session: Session) {
        var updated = session
        updated.isFavorite.toggle()
        do {
            try AppDatabase.shared.dbWriter.write { db in try updated.save(db) }
        } catch {
            errorMessage = "Erro ao atualizar favorito: \(error.localizedDescription)"
        }
    }
}
