//
//  SQLiteRESTDBController.swift
//  SQLiteREST
//
//  Database controller using system SQLite3. Provides all low-level operations
//  for the REST API (db info, raw SQL, schema, CRUD by rowid).
//

import Foundation
import SQLite3

/// SQLite destructor: make a copy of the bound buffer (needed for Swift string/data binding).
private let kSQLiteTransient = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

/// BLOB size threshold in bytes; above this we return "<BLOB>" instead of Base64.
private let kBlobPlaceholderThreshold = 1024

// MARK: - Errors

enum SQLiteRESTDBError: Error {
    case notOpen
    case openFailed(path: String, message: String)
    case prepareFailed(sql: String, message: String)
    case stepFailed(message: String)
    case bindFailed(message: String)
    case invalidTable(name: String)
    case invalidRowid(table: String, rowid: Int64)
}

// MARK: - Controller

final class SQLiteRESTDBController {

    private var db: OpaquePointer?
    private var dbPath: String?
    /// All SQLite access must happen on this queue (one connection = one thread).
    private let dbQueue = DispatchQueue(label: "com.sqliterest.db")

    var isOpen: Bool { dbQueue.sync { db != nil } }

    /// Opens the database at the given path. If already open, closes the previous connection first.
    func open(path: String) throws {
        try dbQueue.sync {
            closeLocked()
            var handle: OpaquePointer?
            let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
            let result = sqlite3_open_v2(path, &handle, flags, nil)
            guard result == SQLITE_OK, let h = handle else {
                let msg = String(cString: sqlite3_errmsg(handle))
                throw SQLiteRESTDBError.openFailed(path: path, message: msg)
            }
            db = h
            dbPath = path
        }
    }

    func close() {
        dbQueue.sync { closeLocked() }
    }

    /// Must be called only from dbQueue.
    private func closeLocked() {
        if let h = db {
            sqlite3_close(h)
            db = nil
        }
        dbPath = nil
    }

    deinit {
        dbQueue.sync { closeLocked() }
    }

    // MARK: - 1. DB Info

    /// Returns dict suitable for GET /db/info: filename, path, sizeBytes, journalMode?, integrity.
    func getDBInfo() throws -> [String: Any] {
        try dbQueue.sync {
            guard let db = db, let path = dbPath else { throw SQLiteRESTDBError.notOpen }

            let url = URL(fileURLWithPath: path)
            let filename = url.lastPathComponent
            let sizeBytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0

            var info: [String: Any] = [
                "filename": filename,
                "path": path,
                "sizeBytes": sizeBytes
            ]

            if let mode = try? getPragma(db, "journal_mode") {
                info["journalMode"] = mode
            }
            if let integrity = try? checkIntegrity(db) {
                info["integrity"] = integrity
            }
            return info
        }
    }

    /// Returns detailed DB metadata for diagnostics and debug dashboards.
    func getDatabaseMetadata() throws -> [String: Any] {
        try dbQueue.sync {
            guard let db = db, let path = dbPath else { throw SQLiteRESTDBError.notOpen }

            let fileURL = URL(fileURLWithPath: path)
            let fileAttrs = try? FileManager.default.attributesOfItem(atPath: path)
            let sizeBytes = (fileAttrs?[.size] as? Int64) ?? 0

            let pageSize = getPragmaInt(db, "page_size") ?? 0
            let pageCount = getPragmaInt(db, "page_count") ?? 0
            let freelistCount = getPragmaInt(db, "freelist_count") ?? 0
            let schemaVersion = getPragmaInt(db, "schema_version") ?? 0
            let userVersion = getPragmaInt(db, "user_version") ?? 0
            let autoVacuum = getPragmaInt(db, "auto_vacuum") ?? 0
            let synchronous = getPragmaInt(db, "synchronous") ?? 0
            let estimatedSizeBytes = pageSize * pageCount

            let sqliteVersion = (try? runQuery(db, sql: "SELECT sqlite_version()", params: []).rows.first?.first as? String) ?? "unknown"

            var info: [String: Any] = [
                "filename": fileURL.lastPathComponent,
                "absolutePath": path,
                "sizeBytes": sizeBytes,
                "estimatedSizeBytes": estimatedSizeBytes,
                "pageSize": pageSize,
                "pageCount": pageCount,
                "freelistCount": freelistCount,
                "schemaVersion": schemaVersion,
                "userVersion": userVersion,
                "autoVacuum": autoVacuum,
                "synchronous": synchronous,
                "sqliteVersion": sqliteVersion
            ]

            if let encoding = try? getPragma(db, "encoding") {
                info["encoding"] = encoding
            }
            if let journalMode = try? getPragma(db, "journal_mode") {
                info["journalMode"] = journalMode
            }
            if let integrity = try? checkIntegrity(db) {
                info["integrity"] = integrity
            }
            return info
        }
    }

    private func getPragma(_ db: OpaquePointer, _ name: String) throws -> String? {
        let sql = "PRAGMA \(name);"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return stringColumn(stmt, 0)
    }

    private func checkIntegrity(_ db: OpaquePointer) throws -> String {
        let sql = "PRAGMA integrity_check;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return "error" }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return "error" }
        return stringColumn(stmt, 0) ?? "error"
    }

    private func getPragmaInt(_ db: OpaquePointer, _ name: String) -> Int64? {
        guard let str = try? getPragma(db, name) else { return nil }
        return Int64(str)
    }

    // MARK: - 2. Raw SQL

    /// Executes raw SQL. Returns either query result (columns + rows) or execute result (rowsAffected, lastInsertId).
    func executeSQL(sql: String, params: [Any] = []) throws -> (type: String, payload: [String: Any]) {
        try dbQueue.sync {
            guard let db = db else { throw SQLiteRESTDBError.notOpen }

            let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let isQuery = trimmed.hasPrefix("SELECT") || trimmed.hasPrefix("WITH")

            if isQuery {
                let (columns, rows) = try runQuery(db, sql: sql, params: params)
                return ("query", [
                    "columns": columns,
                    "rows": rows
                ])
            } else {
                let (rowsAffected, lastInsertId) = try runExecute(db, sql: sql, params: params)
                return ("execute", [
                    "rowsAffected": rowsAffected,
                    "lastInsertId": lastInsertId
                ])
            }
        }
    }

    private func runQuery(_ db: OpaquePointer, sql: String, params: [Any]) throws -> (columns: [String], rows: [[Any]]) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteRESTDBError.prepareFailed(sql: sql, message: String(cString: sqlite3_errmsg(db)))
        }
        try bindParams(stmt!, params: params)
        let columnCount = Int(sqlite3_column_count(stmt))
        let columns = (0..<columnCount).map { String(cString: sqlite3_column_name(stmt, Int32($0))) }
        var rows = [[Any]]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row = [Any]()
            for i in 0..<columnCount {
                row.append(valueFromColumn(stmt!, index: i))
            }
            rows.append(row)
        }
        return (columns, rows)
    }

    private func runExecute(_ db: OpaquePointer, sql: String, params: [Any]) throws -> (rowsAffected: Int, lastInsertId: Int64) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteRESTDBError.prepareFailed(sql: sql, message: String(cString: sqlite3_errmsg(db)))
        }
        try bindParams(stmt!, params: params)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteRESTDBError.stepFailed(message: String(cString: sqlite3_errmsg(db)))
        }
        let rowsAffected = Int(sqlite3_changes(db))
        let lastInsertId = sqlite3_last_insert_rowid(db)
        return (rowsAffected, lastInsertId)
    }

    private func bindParams(_ stmt: OpaquePointer, params: [Any]) throws {
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case is NSNull:
                sqlite3_bind_null(stmt, idx)
            case let v as Int:
                sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Int64:
                sqlite3_bind_int64(stmt, idx, v)
            case let v as Double:
                sqlite3_bind_double(stmt, idx, v)
            case let v as String:
                sqlite3_bind_text(stmt, idx, (v as NSString).utf8String, -1, kSQLiteTransient)
            case let v as Data:
                v.withUnsafeBytes { buf in
                    sqlite3_bind_blob(stmt, idx, buf.baseAddress, Int32(v.count), kSQLiteTransient)
                }
            default:
                sqlite3_bind_text(stmt, idx, (String(describing: p) as NSString).utf8String, -1, kSQLiteTransient)
            }
        }
    }

    private func valueFromColumn(_ stmt: OpaquePointer, index: Int) -> Any {
        let type = sqlite3_column_type(stmt, Int32(index))
        switch type {
        case SQLITE_NULL:
            return NSNull()
        case SQLITE_INTEGER:
            return sqlite3_column_int64(stmt, Int32(index))
        case SQLITE_FLOAT:
            return sqlite3_column_double(stmt, Int32(index))
        case SQLITE_TEXT:
            if let c = sqlite3_column_text(stmt, Int32(index)) {
                return String(cString: c)
            }
            return NSNull()
        case SQLITE_BLOB:
            if let ptr = sqlite3_column_blob(stmt, Int32(index)) {
                let len = Int(sqlite3_column_bytes(stmt, Int32(index)))
                let data = Data(bytes: ptr, count: len)
                if len > kBlobPlaceholderThreshold {
                    return "<BLOB>"
                }
                return data.base64EncodedString()
            }
            return NSNull()
        default:
            return NSNull()
        }
    }

    // MARK: - 3. Schema

    /// Returns list of tables for GET /tables: [{ name, type }].
    func getAllTables() throws -> [[String: Any]] {
        try dbQueue.sync {
            guard let db = db else { throw SQLiteRESTDBError.notOpen }
            let sql = """
                SELECT name, type FROM sqlite_master
                WHERE type IN ('table','view')
                ORDER BY type, name
                """
            let (columns, rows) = try runQuery(db, sql: sql, params: [])
            var result = [[String: Any]]()
            let nameIdx = columns.firstIndex(of: "name") ?? 0
            let typeIdx = columns.firstIndex(of: "type") ?? 1
            for row in rows {
                let name = (row[nameIdx] as? String) ?? ""
                var typeStr = (row[typeIdx] as? String) ?? "table"
                if name.hasPrefix("sqlite_") {
                    typeStr = "system"
                }
                result.append(["name": name, "type": typeStr])
            }
            return result
        }
    }

    /// Returns schema for GET /tables/{tableName}/schema: name, sql, columns.
    func getTableSchema(tableName: String) throws -> [String: Any] {
        try dbQueue.sync {
            guard let db = db else { throw SQLiteRESTDBError.notOpen }
            let safe = sanitizeIdentifier(tableName)
            let (_, tableRows) = try runQuery(db, sql: "SELECT name, sql FROM sqlite_master WHERE type IN ('table','view') AND name = ?", params: [safe])
            guard let first = tableRows.first, let name = first[0] as? String, let sql = first[1] as? String else {
                throw SQLiteRESTDBError.invalidTable(name: tableName)
            }
            let tableInfo = try runQuery(db, sql: "PRAGMA table_info(\(safe))", params: [])
            let columns: [[String: Any]] = tableInfo.1.map { row in
                let cid = (row[0] as? Int64) ?? 0
                let colName = (row[1] as? String) ?? ""
                let type = (row[2] as? String) ?? ""
                let notnull = (row[3] as? Int64) ?? 0
                let pk = (row[5] as? Int64) ?? 0
                return [
                    "cid": cid,
                    "name": colName,
                    "type": type,
                    "pk": pk,
                    "notnull": notnull
                ] as [String: Any]
            }
            return [
                "name": name,
                "sql": sql,
                "columns": columns
            ] as [String: Any]
        }
    }

    // MARK: - 4. Data CRUD

    /// List rows with pagination, sort, and filters. Columns always include rowid first.
    func listRows(
        tableName: String,
        page: Int,
        perPage: Int,
        sort: String?,
        order: String?,
        columnFilters: [String: String],
        filterSQL: String?
    ) throws -> (columns: [String], rows: [[Any]], totalRows: Int) {
        try dbQueue.sync {
            guard let db = db else { throw SQLiteRESTDBError.notOpen }
            let safe = sanitizeIdentifier(tableName)
            try validateTableExists(db, tableName: safe)

            let offset = max(0, page - 1) * max(1, perPage)
            let limit = max(1, min(perPage, 1000))
            let orderDir = (order?.uppercased() == "DESC") ? "DESC" : "ASC"
            let sortCol = sort.flatMap { sanitizeIdentifier($0) } ?? "rowid"

            var whereClause = ""
            var params: [Any] = []

            if !columnFilters.isEmpty {
                let filterKeys = columnFilters.keys.sorted()
                let parts = filterKeys.map { "\(sanitizeIdentifier($0)) = ?" }
                params.append(contentsOf: filterKeys.map { columnFilters[$0] ?? "" })
                whereClause = " WHERE " + parts.joined(separator: " AND ")
            }
            if let extra = filterSQL, !extra.isEmpty {
                if whereClause.isEmpty {
                    whereClause = " WHERE " + extra
                } else {
                    whereClause += " AND (" + extra + ")"
                }
            }

            let countSQL = "SELECT COUNT(*) FROM \(safe)" + whereClause
            let (_, countRows) = try runQuery(db, sql: countSQL, params: params)
            let totalRows = (countRows.first?.first as? Int64) ?? 0

            let orderClause = " ORDER BY \(sortCol) \(orderDir)"
            let listSQL = "SELECT rowid, * FROM \(safe)" + whereClause + orderClause + " LIMIT ? OFFSET ?"
            var listParams = params
            listParams.append(limit)
            listParams.append(offset)
            let (cols, rows) = try runQuery(db, sql: listSQL, params: listParams)
            return (cols, rows, Int(totalRows))
        }
    }

    /// Insert a row; returns new rowid.
    func createRow(tableName: String, fields: [String: Any]) throws -> Int64 {
        try dbQueue.sync {
            guard let db = db else { throw SQLiteRESTDBError.notOpen }
            let safe = sanitizeIdentifier(tableName)
            try validateTableExists(db, tableName: safe)
            let keys = Array(fields.keys)
            let columnList = keys.map { sanitizeIdentifier($0) }.joined(separator: ", ")
            let placeholders = keys.map { _ in "?" }.joined(separator: ", ")
            let sql = "INSERT INTO \(safe) (\(columnList)) VALUES (\(placeholders))"
            let values = keys.map { fields[$0] ?? NSNull() }
            let (_, lastId) = try runExecute(db, sql: sql, params: values)
            return lastId
        }
    }

    /// Update row by rowid (PATCH semantics). Returns rowsAffected.
    func updateRow(tableName: String, rowid: Int64, fields: [String: Any]) throws -> Int {
        try dbQueue.sync {
            guard let db = db else { throw SQLiteRESTDBError.notOpen }
            let safe = sanitizeIdentifier(tableName)
            try validateTableExists(db, tableName: safe)
            guard !fields.isEmpty else { return 0 }
            let keys = Array(fields.keys).sorted()
            let setParts = keys.map { "\(sanitizeIdentifier($0)) = ?" }
            let sql = "UPDATE \(safe) SET \(setParts.joined(separator: ", ")) WHERE rowid = ?"
            var params = keys.map { fields[$0] ?? NSNull() }
            params.append(rowid)
            let (rowsAffected, _) = try runExecute(db, sql: sql, params: params)
            return rowsAffected
        }
    }

    /// Delete row by rowid. Returns rowsAffected.
    func deleteRow(tableName: String, rowid: Int64) throws -> Int {
        try dbQueue.sync {
            guard let db = db else { throw SQLiteRESTDBError.notOpen }
            let safe = sanitizeIdentifier(tableName)
            try validateTableExists(db, tableName: safe)
            let sql = "DELETE FROM \(safe) WHERE rowid = ?"
            let (rowsAffected, _) = try runExecute(db, sql: sql, params: [rowid])
            return rowsAffected
        }
    }

    // MARK: - Helpers

    private func validateTableExists(_ db: OpaquePointer, tableName: String) throws {
        let (_, rows) = try runQuery(db, sql: "SELECT 1 FROM sqlite_master WHERE type IN ('table','view') AND name = ?", params: [tableName])
        if rows.isEmpty {
            throw SQLiteRESTDBError.invalidTable(name: tableName)
        }
    }

    /// Allowed: alphanumeric and underscore. Else throws or returns safe substring.
    private func sanitizeIdentifier(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        let filtered = name.unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(filtered))
    }

    private func stringColumn(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }
}
