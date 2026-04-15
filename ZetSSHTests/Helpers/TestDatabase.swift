import Foundation
import GRDB
@testable import zetssh

/// Creates an in-memory DatabaseQueue with the same migrations as AppDatabase.
func makeTestDatabase() throws -> DatabaseWriter {
    let queue = try DatabaseQueue()
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

    try migrator.migrate(queue)
    return queue
}
