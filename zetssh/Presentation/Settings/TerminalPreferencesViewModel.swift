import Foundation
import GRDB
import Combine

@MainActor
final class TerminalPreferencesViewModel: ObservableObject {

    @Published var profiles: [TerminalProfile] = []
    @Published var activeProfile: TerminalProfile?

    private let db: AppDatabase

    init(db: AppDatabase = .shared) {
        self.db = db
        Task { await load() }
    }

    // MARK: - Load

    func load() async {
        do {
            let result = try await db.dbWriter.read { db in
                try TerminalProfile.fetchAll(db)
            }
            self.profiles = result
            self.activeProfile = result.first(where: { $0.isDefault }) ?? result.first
        } catch {
            AppLogger.shared.log("TerminalPreferencesViewModel.load error: \(error)", category: .database, level: .error)
        }
    }

    // MARK: - Set Active Profile

    /// Marks `profile` as the default and clears isDefault on all others.
    func setActive(profile: TerminalProfile) {
        Task {
            do {
                try await db.dbWriter.write { db in
                    try db.execute(sql: "UPDATE terminalProfile SET isDefault = 0")
                    var updated = profile
                    updated.isDefault = true
                    try updated.update(db)
                }
                await load()
            } catch {
                AppLogger.shared.log("TerminalPreferencesViewModel.setActive error: \(error)", category: .database, level: .error)
            }
        }
    }

    // MARK: - Update Font Size on Active Profile

    func updateFontSize(_ size: Double) {
        guard var profile = activeProfile else { return }
        profile.fontSize = max(8, min(size, 32))
        Task {
            do {
                try await db.dbWriter.write { db in
                    try profile.update(db)
                }
                await load()
            } catch {
                AppLogger.shared.log("TerminalPreferencesViewModel.updateFontSize error: \(error)", category: .database, level: .error)
            }
        }
    }
}
