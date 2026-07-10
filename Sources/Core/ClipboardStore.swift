import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite-backed metadata store. Image bytes remain files in Application Support.
final class ClipboardStore {
    private var database: OpaquePointer?

    init(databaseURL: URL) throws {
        guard sqlite3_open_v2(databaseURL.path, &database,
                              SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                              nil) == SQLITE_OK else {
            throw StoreError.openFailed(message: Self.errorMessage(database))
        }
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
        try execute("""
            CREATE TABLE IF NOT EXISTS clipboard_items (
                id TEXT PRIMARY KEY NOT NULL,
                type TEXT NOT NULL,
                content TEXT NOT NULL,
                timestamp REAL NOT NULL,
                is_favorite INTEGER NOT NULL DEFAULT 0,
                copy_count INTEGER NOT NULL DEFAULT 0,
                tags_json TEXT NOT NULL DEFAULT '[]'
            )
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_clipboard_timestamp ON clipboard_items(timestamp DESC)")
        try execute("CREATE INDEX IF NOT EXISTS idx_clipboard_favorite_timestamp ON clipboard_items(is_favorite, timestamp DESC)")
        try execute("CREATE INDEX IF NOT EXISTS idx_clipboard_duplicate ON clipboard_items(type, content)")
    }

    deinit { sqlite3_close(database) }

    struct Query: Equatable {
        var favoritesOnly = false
        var tag: String?
        var searchText = ""
    }

    enum StoreError: Error {
        case openFailed(message: String)
        case sqlite(message: String)
    }

    func isEmpty() throws -> Bool { try count(Query()) == 0 }

    func count(_ query: Query) throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM clipboard_items\(whereClause(for: query))")
        defer { sqlite3_finalize(statement) }
        try bindQuery(query, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw sqliteError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func favoriteCount() throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM clipboard_items WHERE is_favorite = 1")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw sqliteError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func favoriteTags() throws -> [String] {
        let statement = try prepare("SELECT tags_json FROM clipboard_items WHERE is_favorite = 1")
        defer { sqlite3_finalize(statement) }
        var tags = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            tags.formUnion(decodeTags(text(at: 0, statement)))
        }
        return tags.sorted()
    }

    func allFavorites() throws -> [ClipboardItem] {
        try page(for: Query(favoritesOnly: true), offset: 0, limit: Int.max)
    }

    func page(for query: Query, offset: Int, limit: Int) throws -> [ClipboardItem] {
        let order = query.favoritesOnly ? "copy_count DESC, timestamp DESC" : "timestamp DESC"
        let statement = try prepare("""
            SELECT id, type, content, timestamp, is_favorite, copy_count, tags_json
            FROM clipboard_items\(whereClause(for: query))
            ORDER BY \(order) LIMIT ? OFFSET ?
        """)
        defer { sqlite3_finalize(statement) }
        var index: Int32 = try bindQuery(query, to: statement)
        try bind(Int64(limit), at: index, to: statement); index += 1
        try bind(Int64(offset), at: index, to: statement)

        var result: [ClipboardItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let type = ClipboardItem.ItemType(rawValue: text(at: 1, statement)) else { continue }
            result.append(ClipboardItem(
                id: text(at: 0, statement), type: type, content: text(at: 2, statement),
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                isFavorite: sqlite3_column_int(statement, 4) != 0,
                copyCount: Int(sqlite3_column_int64(statement, 5)), tags: decodeTags(text(at: 6, statement))
            ))
        }
        return result
    }

    func duplicate(type: ClipboardItem.ItemType, content: String) throws -> ClipboardItem? {
        let statement = try prepare("""
            SELECT id, type, content, timestamp, is_favorite, copy_count, tags_json
            FROM clipboard_items WHERE type = ? AND content = ? LIMIT 1
        """)
        defer { sqlite3_finalize(statement) }
        try bind(type.rawValue, at: 1, to: statement); try bind(content, at: 2, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let itemType = ClipboardItem.ItemType(rawValue: text(at: 1, statement)) else { return nil }
        return ClipboardItem(id: text(at: 0, statement), type: itemType, content: text(at: 2, statement),
                             timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                             isFavorite: sqlite3_column_int(statement, 4) != 0,
                             copyCount: Int(sqlite3_column_int64(statement, 5)), tags: decodeTags(text(at: 6, statement)))
    }

    func insert(_ item: ClipboardItem) throws {
        let statement = try prepare("INSERT INTO clipboard_items (id, type, content, timestamp, is_favorite, copy_count, tags_json) VALUES (?, ?, ?, ?, ?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        try bind(item.id, at: 1, to: statement); try bind(item.type.rawValue, at: 2, to: statement)
        try bind(item.content, at: 3, to: statement); try bind(item.timestamp.timeIntervalSince1970, at: 4, to: statement)
        try bind(item.isFavorite ? 1 : 0, at: 5, to: statement); try bind(Int64(item.copyCount), at: 6, to: statement)
        try bind(encodeTags(item.tags), at: 7, to: statement)
        try stepDone(statement)
    }

    func update(_ item: ClipboardItem) throws {
        let statement = try prepare("UPDATE clipboard_items SET content = ?, timestamp = ?, is_favorite = ?, copy_count = ?, tags_json = ? WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try bind(item.content, at: 1, to: statement); try bind(item.timestamp.timeIntervalSince1970, at: 2, to: statement)
        try bind(item.isFavorite ? 1 : 0, at: 3, to: statement); try bind(Int64(item.copyCount), at: 4, to: statement)
        try bind(encodeTags(item.tags), at: 5, to: statement); try bind(item.id, at: 6, to: statement)
        try stepDone(statement)
    }

    func delete(id: String) throws { try executeBound("DELETE FROM clipboard_items WHERE id = ?", values: [id]) }
    func deleteAll(favorites: Bool) throws { try execute("DELETE FROM clipboard_items WHERE is_favorite = \(favorites ? 1 : 0)") }

    func imageFilenames(favorites: Bool) throws -> [String] {
        let statement = try prepare("SELECT content FROM clipboard_items WHERE type = 'image' AND is_favorite = ?")
        defer { sqlite3_finalize(statement) }
        try bind(favorites ? 1 : 0, at: 1, to: statement)
        var filenames: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW { filenames.append(text(at: 0, statement)) }
        return filenames
    }

    func importLegacy(_ items: [ClipboardItem]) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            for item in items { try insert(item) }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func whereClause(for query: Query) -> String {
        var clauses: [String] = []
        if query.favoritesOnly { clauses.append("is_favorite = 1") }
        if query.tag != nil { clauses.append("tags_json LIKE ?") }
        if !query.searchText.isEmpty { clauses.append("content LIKE ? COLLATE NOCASE") }
        return clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
    }

    @discardableResult private func bindQuery(_ query: Query, to statement: OpaquePointer?) throws -> Int32 {
        var index: Int32 = 1
        if let tag = query.tag { try bind("%\"\(tag)\"%", at: index, to: statement); index += 1 }
        if !query.searchText.isEmpty { try bind("%\(query.searchText)%", at: index, to: statement); index += 1 }
        return index
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw sqliteError() }
        return statement
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw sqliteError() }
    }
    private func executeBound(_ sql: String, values: [String]) throws {
        let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() { try bind(value, at: Int32(offset + 1), to: statement) }
        try stepDone(statement)
    }
    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw sqliteError() }
    }
    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer?) throws {
        guard sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) == SQLITE_OK else { throw sqliteError() }
    }
    private func bind(_ value: Int64, at index: Int32, to statement: OpaquePointer?) throws {
        guard sqlite3_bind_int64(statement, index, value) == SQLITE_OK else { throw sqliteError() }
    }
    private func bind(_ value: Int, at index: Int32, to statement: OpaquePointer?) throws { try bind(Int64(value), at: index, to: statement) }
    private func bind(_ value: Double, at index: Int32, to statement: OpaquePointer?) throws {
        guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else { throw sqliteError() }
    }
    private func text(at index: Int32, _ statement: OpaquePointer?) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }
    private func encodeTags(_ tags: [String]) -> String { (try? String(data: JSONEncoder().encode(tags), encoding: .utf8)) ?? "[]" }
    private func decodeTags(_ string: String) -> [String] { (try? JSONDecoder().decode([String].self, from: Data(string.utf8))) ?? [] }
    private func sqliteError() -> StoreError { .sqlite(message: Self.errorMessage(database)) }
    private static func errorMessage(_ database: OpaquePointer?) -> String { database.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unknown SQLite error" }
}
