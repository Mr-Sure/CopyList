import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite-backed metadata store. Image bytes remain files in Application Support.
final class ClipboardStore {
    private var database: OpaquePointer?

    convenience init(databaseURL: URL) throws {
        try self.init(databasePath: databaseURL.path)
    }

    /// 内存数据库：磁盘库损坏时的兜底，保证应用仍可启动
    convenience init(inMemory: Bool) throws {
        try self.init(databasePath: ":memory:")
    }

    private init(databasePath: String) throws {
        guard sqlite3_open_v2(databasePath, &database,
                              SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                              nil) == SQLITE_OK else {
            throw StoreError.openFailed(message: Self.errorMessage(database))
        }
        do {
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
            // 图片内容哈希列（向下兼容）：旧库探测到缺列才补列，避免每次启动的重复 ALTER 报错
            do {
                try execute("SELECT content_hash FROM clipboard_items LIMIT 0")
            } catch {
                do {
                    try execute("ALTER TABLE clipboard_items ADD COLUMN content_hash TEXT")
                } catch {
                    // 补列失败（如瞬时时锁）只降级图片去重能力，不判定为数据库损坏
                    NSLog("CopyList: ⚠️ content_hash 列不可用，图片内容去重将被跳过: \(Self.errorMessage(database))")
                }
            }
            try execute("CREATE INDEX IF NOT EXISTS idx_clipboard_timestamp ON clipboard_items(timestamp DESC)")
            try execute("CREATE INDEX IF NOT EXISTS idx_clipboard_favorite_timestamp ON clipboard_items(is_favorite, timestamp DESC)")
            try execute("CREATE INDEX IF NOT EXISTS idx_clipboard_duplicate ON clipboard_items(type, content)")
            do {
                try execute("CREATE INDEX IF NOT EXISTS idx_clipboard_hash ON clipboard_items(type, content_hash)")
            } catch {
                NSLog("CopyList: ⚠️ content_hash 索引创建失败（图片去重退化为全表扫描）: \(Self.errorMessage(database))")
            }
        } catch {
            // 初始化失败时关闭句柄，避免文件描述符泄漏
            sqlite3_close(database)
            database = nil
            throw error
        }
    }

    deinit { sqlite3_close(database) }

    struct Query: Equatable {
        var favoritesOnly = false
        var tag: String?
        var type: ClipboardItem.ItemType?
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

    /// 图片按内容哈希去重：哈希为 NULL 的旧记录不会被匹配到（会走正常插入并带上新哈希）
    func imageDuplicate(hash: String) throws -> ClipboardItem? {
        let statement = try prepare("""
            SELECT id, type, content, timestamp, is_favorite, copy_count, tags_json
            FROM clipboard_items WHERE type = 'image' AND content_hash = ? LIMIT 1
        """)
        defer { sqlite3_finalize(statement) }
        try bind(hash, at: 1, to: statement)
        if sqlite3_step(statement) == SQLITE_ROW {
            return self.imageItem(from: statement)
        }
        return nil
    }

    private func imageItem(from statement: OpaquePointer?) -> ClipboardItem {
        ClipboardItem(id: text(at: 0, statement), type: .image, content: text(at: 2, statement),
                      timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                      isFavorite: sqlite3_column_int(statement, 4) != 0,
                      copyCount: Int(sqlite3_column_int64(statement, 5)), tags: decodeTags(text(at: 6, statement)))
    }

    /// 某图片文件名仍被多少条记录引用（删除记录时用于保守判断是否可删磁盘资产）
    func imageReferenceCount(fileName: String) throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM clipboard_items WHERE type = 'image' AND content = ?")
        defer { sqlite3_finalize(statement) }
        try bind(fileName, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw sqliteError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// 历史上限：非收藏记录超过 maxItems 时删除最旧的一部分，返回可安全清理的图片文件名。
    /// 使用 NOT IN (SELECT ... LIMIT ?) 而非动态占位符，避免超出 SQLite 变量数上限（32766）。
    func pruneHistory(maxItems: Int) throws -> [String] {
        let nonFavoriteCount = try countNonFavorites()
        guard nonFavoriteCount > maxItems else { return [] }

        // 先收集将被删除的最旧非收藏图片的文件名（保留窗口 = 最新的 maxItems 条非收藏）
        let select = try prepare("""
            SELECT content FROM clipboard_items
            WHERE is_favorite = 0 AND type = 'image' AND id NOT IN (
                SELECT id FROM clipboard_items WHERE is_favorite = 0
                ORDER BY timestamp DESC LIMIT ?
            )
        """)
        var candidateImageFiles: [String] = []
        do {
            defer { sqlite3_finalize(select) }
            try bind(Int64(maxItems), at: 1, to: select)
            while sqlite3_step(select) == SQLITE_ROW {
                let content = text(at: 0, select)
                if !candidateImageFiles.contains(content) { candidateImageFiles.append(content) }
            }
        }

        // 删除保留窗口之外的最旧非收藏记录
        let deleteStatement = try prepare("""
            DELETE FROM clipboard_items WHERE is_favorite = 0 AND id NOT IN (
                SELECT id FROM clipboard_items WHERE is_favorite = 0
                ORDER BY timestamp DESC LIMIT ?
            )
        """)
        defer { sqlite3_finalize(deleteStatement) }
        try bind(Int64(maxItems), at: 1, to: deleteStatement)
        try stepDone(deleteStatement)

        // 删除完成后，仍被现存图片记录引用的文件不能删磁盘资产
        guard !candidateImageFiles.isEmpty else { return [] }
        let referenced = Set(try allImageFilenames())
        return candidateImageFiles.filter { !referenced.contains($0) }
    }

    func countNonFavorites() throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM clipboard_items WHERE is_favorite = 0")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw sqliteError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func allImageFilenames() throws -> [String] {
        let statement = try prepare("SELECT content FROM clipboard_items WHERE type = 'image'")
        defer { sqlite3_finalize(statement) }
        var filenames: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW { filenames.append(text(at: 0, statement)) }
        return filenames
    }

    func insert(_ item: ClipboardItem, contentHash: String? = nil) throws {
        let statement = try prepare("INSERT INTO clipboard_items (id, type, content, timestamp, is_favorite, copy_count, tags_json, content_hash) VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        try bind(item.id, at: 1, to: statement); try bind(item.type.rawValue, at: 2, to: statement)
        try bind(item.content, at: 3, to: statement); try bind(item.timestamp.timeIntervalSince1970, at: 4, to: statement)
        try bind(item.isFavorite ? 1 : 0, at: 5, to: statement); try bind(Int64(item.copyCount), at: 6, to: statement)
        try bind(encodeTags(item.tags), at: 7, to: statement)
        if let contentHash {
            try bind(contentHash, at: 8, to: statement)
        } else {
            try bindNil(at: 8, to: statement)
        }
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

    /// LIKE 占位符：绑定值需先经 escapeLike 转义并预包裹 % 通配符
    private static let likePlaceholder = "? ESCAPE '\\'"

    private func whereClause(for query: Query) -> String {
        var clauses: [String] = []
        if query.favoritesOnly { clauses.append("is_favorite = 1") }
        if query.tag != nil { clauses.append("tags_json LIKE \(Self.likePlaceholder)") }
        if query.type != nil { clauses.append("type = ?") }
        if !query.searchText.isEmpty {
            // 搜索同时匹配正文与标签：用户按“安全”搜索时，打上“安全”标签的记录也能被找到
            clauses.append("(content COLLATE NOCASE LIKE \(Self.likePlaceholder) OR tags_json COLLATE NOCASE LIKE \(Self.likePlaceholder))")
        }
        return clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
    }

    @discardableResult private func bindQuery(_ query: Query, to statement: OpaquePointer?) throws -> Int32 {
        var index: Int32 = 1
        if let tag = query.tag { try bind("%\"\(escapeLike(tag))\"%", at: index, to: statement); index += 1 }
        if let type = query.type { try bind(type.rawValue, at: index, to: statement); index += 1 }
        if !query.searchText.isEmpty {
            let pattern = "%\(escapeLike(query.searchText))%"
            try bind(pattern, at: index, to: statement); index += 1   // 匹配正文 content
            try bind(pattern, at: index, to: statement); index += 1   // 匹配标签 tags_json
        }
        return index
    }

    /// 转义 LIKE 通配符，保证搜索 100%、a_b 等文本时的语义正确
    private func escapeLike(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "%", with: "\\%")
             .replacingOccurrences(of: "_", with: "\\_")
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
    private func bindNil(at index: Int32, to statement: OpaquePointer?) throws {
        guard sqlite3_bind_null(statement, index) == SQLITE_OK else { throw sqliteError() }
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
