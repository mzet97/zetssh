// NOTE: GRDB uses SQLite. Swift Package Manager doesn't officially support SQLCipher drop-in natively without a fork like SQLCipher.swift.
// For this MVP, we are simulating the db.usePassphrase by acknowledging the need.
// In a full production build, we would use CocoaPods or a custom XCFrame to link SQLCipher instead of standard SQLite.
// Since standard GRDB via SPM doesn't include SQLCipher, we'll keep the key generation but omit `usePassphrase` until the C-Library is swapped.

import Foundation
import AppKit
import GRDB

final class AppDatabase {
    static let shared: AppDatabase = {
        guard let db = AppDatabase.makeOrAlert() else {
            // makeOrAlert termina o app; esta linha nunca é atingida
            fatalError("unreachable")
        }
        return db
    }()

    let dbWriter: DatabaseWriter

    static func makeOrAlert() -> AppDatabase? {
        do {
            return try AppDatabase()
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Erro ao inicializar o banco de dados"
                alert.informativeText = error.localizedDescription + "\n\nO aplicativo não pode continuar."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "Sair")
                alert.runModal()
                NSApp.terminate(nil)
            }
            return nil
        }
    }

    private init() throws {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = appSupportURL.appendingPathComponent("ZetSSH", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let databaseURL = directoryURL.appendingPathComponent("db.sqlite")

        let config = Configuration()

        // Generate/retrieve the 256-bit key from Keychain (used when SQLCipher is integrated).
        _ = try KeychainService.shared.getOrCreateDatabaseEncryptionKey()

        // To enable SQLCipher: link SQLCipher via CocoaPods/XCFramework, then uncomment:
        // config.prepareDatabase { db in try db.usePassphrase(encryptionKey) }

        dbWriter = try DatabasePool(path: databaseURL.path, configuration: config)
        try migrator.migrate(dbWriter)

        AppLogger.shared.log("Database inicializado em \(databaseURL.path)", category: .database, level: .info)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "folder") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("icon", .text)
            }

            try db.create(table: "session") { t in
                t.column("id", .text).primaryKey()
                t.column("folderId", .text).references("folder", onDelete: .setNull)
                t.column("name", .text).notNull()
                t.column("host", .text).notNull()
                t.column("port", .integer).notNull().defaults(to: 22)
                t.column("username", .text).notNull()
            }
        }

        migrator.registerMigration("v2") { db in
            try db.create(table: "knownHost") { t in
                t.column("host",        .text).notNull()
                t.column("port",        .integer).notNull()
                t.column("algorithm",   .text).notNull()
                t.column("fingerprint", .text).notNull()
                t.column("addedAt",     .datetime).notNull()
                t.primaryKey(["host", "port", "algorithm"])
            }
        }

        migrator.registerMigration("v3") { db in
            try db.alter(table: "session") { t in
                t.add(column: "privateKeyPath", .text)
            }
        }

        return migrator
    }
}
