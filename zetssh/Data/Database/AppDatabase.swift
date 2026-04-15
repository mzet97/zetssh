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

        var config = Configuration()

        let encryptionKey = try KeychainService.shared.getOrCreateDatabaseEncryptionKey()
        config.prepareDatabase { db in
            try db.usePassphrase(encryptionKey)
        }

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

        migrator.registerMigration("v4") { db in
            try db.create(table: "terminalProfile") { t in
                t.column("id",         .text).primaryKey()
                t.column("name",       .text).notNull()
                t.column("foreground", .text).notNull()
                t.column("background", .text).notNull()
                t.column("cursor",     .text).notNull()
                t.column("fontName",   .text).notNull()
                t.column("fontSize",   .double).notNull()
                t.column("isDefault",  .boolean).notNull().defaults(to: false)
            }

            let themes: [(name: String, bg: String, fg: String, cursor: String)] = [
                ("Dracula",        "#282A36", "#F8F8F2", "#F8F8F2"),
                ("Solarized Dark", "#002B36", "#839496", "#839496"),
                ("One Dark",       "#282C34", "#ABB2BF", "#528BFF"),
                ("Default Dark",   "#1E1E1E", "#D4D4D4", "#D4D4D4"),
                ("Gruvbox",        "#282828", "#EBDBB2", "#EBDBB2"),
            ]

            for (index, theme) in themes.enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO terminalProfile
                            (id, name, foreground, background, cursor, fontName, fontSize, isDefault)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        UUID().uuidString,
                        theme.name,
                        theme.fg,
                        theme.bg,
                        theme.cursor,
                        "Menlo",
                        13.0,
                        index == 0 ? 1 : 0
                    ]
                )
            }
        }

        return migrator
    }
}
