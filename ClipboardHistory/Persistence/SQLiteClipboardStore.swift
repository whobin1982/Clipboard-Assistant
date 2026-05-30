import Foundation
import SQLite3

final class SQLiteClipboardStore: ClipboardStore {
    private let db: OpaquePointer?

    init(databaseURL: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            if let database {
                sqlite3_close(database)
            }
            throw DatabaseError.openFailed
        }

        do {
            try DatabaseMigrator.migrate(database)
        } catch {
            sqlite3_close(database)
            throw error
        }

        db = database
    }

    deinit {
        sqlite3_close(db)
    }

    static func temporary() throws -> SQLiteClipboardStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        return try SQLiteClipboardStore(databaseURL: url)
    }

    func insert(_ item: ClipboardItem) throws {
        let sql = """
        INSERT OR REPLACE INTO clipboard_items (
            id, kind, copied_at, last_used_at, is_favorite, text, image_path, thumbnail_path
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, item.id.uuidString, -1, SQLiteClipboardStore.transientDestructor)
        sqlite3_bind_text(statement, 2, item.kind.rawValue, -1, SQLiteClipboardStore.transientDestructor)
        sqlite3_bind_double(statement, 3, item.copiedAt.timeIntervalSince1970)
        bindOptionalDate(item.lastUsedAt, to: statement, at: 4)
        sqlite3_bind_int(statement, 5, item.isFavorite ? 1 : 0)
        bindOptionalText(item.text, to: statement, at: 6)
        bindOptionalText(item.imagePath, to: statement, at: 7)
        bindOptionalText(item.thumbnailPath, to: statement, at: 8)

        try stepDone(statement)
    }

    func fetchAll() throws -> [ClipboardItem] {
        let sql = """
        SELECT id, kind, copied_at, last_used_at, is_favorite, text, image_path, thumbnail_path
        FROM clipboard_items
        ORDER BY is_favorite DESC, copied_at DESC;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        var items: [ClipboardItem] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return items
            }
            guard result == SQLITE_ROW else {
                throw DatabaseError.executeFailed(errorMessage)
            }
            items.append(try item(from: statement))
        }
    }

    func setFavorite(id: UUID, isFavorite: Bool) throws {
        let statement = try prepare("UPDATE clipboard_items SET is_favorite = ? WHERE id = ?;")
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, isFavorite ? 1 : 0)
        sqlite3_bind_text(statement, 2, id.uuidString, -1, SQLiteClipboardStore.transientDestructor)

        try stepDone(statement)
    }

    func delete(id: UUID) throws {
        let statement = try prepare("DELETE FROM clipboard_items WHERE id = ?;")
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, id.uuidString, -1, SQLiteClipboardStore.transientDestructor)

        try stepDone(statement)
    }

    func deleteNonFavorites(olderThan cutoff: Date) throws {
        let statement = try prepare("DELETE FROM clipboard_items WHERE is_favorite = 0 AND copied_at < ?;")
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)

        try stepDone(statement)
    }

    func deleteAll(includeFavorites: Bool) throws {
        let sql = includeFavorites
            ? "DELETE FROM clipboard_items;"
            : "DELETE FROM clipboard_items WHERE is_favorite = 0;"
        try DatabaseMigrator.execute(sql, db: db)
    }
}

private extension SQLiteClipboardStore {
    static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    var errorMessage: String {
        sqlite3_errmsg(db).map { String(cString: $0) } ?? "Unknown SQLite error"
    }

    func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(errorMessage)
        }
        return statement
    }

    func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.executeFailed(errorMessage)
        }
    }

    func bindOptionalText(_ value: String?, to statement: OpaquePointer?, at index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, SQLiteClipboardStore.transientDestructor)
    }

    func bindOptionalDate(_ value: Date?, to statement: OpaquePointer?, at index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
    }

    func optionalText(from statement: OpaquePointer?, at index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    func optionalDate(from statement: OpaquePointer?, at index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    func item(from statement: OpaquePointer?) throws -> ClipboardItem {
        guard let idText = optionalText(from: statement, at: 0),
              let id = UUID(uuidString: idText) else {
            throw DatabaseError.executeFailed("Invalid clipboard item id in database")
        }
        guard let kindText = optionalText(from: statement, at: 1),
              let kind = ClipboardItemKind(rawValue: kindText) else {
            throw DatabaseError.executeFailed("Invalid clipboard item kind in database")
        }

        return ClipboardItem(
            id: id,
            kind: kind,
            copiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
            lastUsedAt: optionalDate(from: statement, at: 3),
            isFavorite: sqlite3_column_int(statement, 4) != 0,
            text: optionalText(from: statement, at: 5),
            imagePath: optionalText(from: statement, at: 6),
            thumbnailPath: optionalText(from: statement, at: 7)
        )
    }
}
