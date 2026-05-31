import Foundation
import SQLite3

/// SQLite 数据库操作中向上抛出的错误类型。
enum DatabaseError: Error {
    case openFailed
    case executeFailed(String)
    case prepareFailed(String)
}

/// 负责创建和升级数据库结构。
enum DatabaseMigrator {
    /// 创建当前版本所需的剪贴板历史表和排序索引。
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

    /// 执行一段无返回结果的 SQL，并把 SQLite 错误消息转换为 Swift 错误。
    static func execute(_ sql: String, db: OpaquePointer?) throws {
        var error: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "Unknown SQLite error"
            sqlite3_free(error)
            throw DatabaseError.executeFailed(message)
        }
    }
}
