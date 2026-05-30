import Foundation
import SQLite3

enum DatabaseError: Error {
    case openFailed
    case executeFailed(String)
    case prepareFailed(String)
}

enum DatabaseMigrator {
    static func migrate(_ db: OpaquePointer?) throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            copied_at REAL NOT NULL,
            last_used_at REAL,
            is_favorite INTEGER NOT NULL,
            text TEXT,
            image_path TEXT,
            thumbnail_path TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_clipboard_items_copied_at ON clipboard_items(copied_at DESC);
        """
        try execute(sql, db: db)
    }

    static func execute(_ sql: String, db: OpaquePointer?) throws {
        var error: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "Unknown SQLite error"
            sqlite3_free(error)
            throw DatabaseError.executeFailed(message)
        }
    }
}
