//
//  SQLiteRESTAPIServer.swift
//  SQLiteREST
//
//  HTTP API server using GCDWebServer. Serves /api/v1/* with envelope JSON responses.
//  Depends on SQLiteRESTDBController for all database operations.
//

import Foundation
import GCDWebServer
import UIKit

private let apiPrefix = "/api/v1"

// MARK: - Response Helpers

private func envelopeSuccess(data: Any, meta: [String: Any]? = nil) -> [String: Any] {
    var body: [String: Any] = ["success": true, "data": data]
    if let m = meta, !m.isEmpty { body["meta"] = m }
    return body
}

private func envelopeError(code: String, message: String) -> [String: Any] {
    return [
        "success": false,
        "error": [
            "code": code,
            "message": message
        ] as [String: Any]
    ]
}

private func jsonResponse(_ body: [String: Any], statusCode: Int = 200) -> GCDWebServerResponse? {
    guard let json = try? JSONSerialization.data(withJSONObject: body) else {
        return nil
    }
    let response = GCDWebServerDataResponse(data: json, contentType: "application/json")
    response.statusCode = statusCode
    return response
}

// MARK: - API Server

@objcMembers
public final class SQLiteRESTAPIServer: NSObject {

    private let webServer = GCDWebServer()
    private let dbController = SQLiteRESTDBController()

    public override init() {
        super.init()
        setupHandlers()
    }

    /// Opens the database and starts the HTTP server. Call from main thread.
    public func start(databasePath: String, port: UInt = 0) throws {
        try dbController.open(path: databasePath)
        let options: [String: Any] = [
            GCDWebServerOption_Port: port,
            GCDWebServerOption_BindToLocalhost: false
        ]
        try webServer.start(options: options)
    }

    public func stop() {
        webServer.stop()
        dbController.close()
    }

    public var serverURL: URL? { webServer.serverURL }
    public var isRunning: Bool { webServer.isRunning }

    // MARK: - Route Registration

    private func setupHandlers() {
        // GET / and GET /index.html — serve Web UI
        webServer.addHandler(forMethod: "GET", path: "/", request: GCDWebServerRequest.self) { [weak self] _ in
            self?.handleWebUI() ?? GCDWebServerErrorResponse(statusCode: 404)
        }
        webServer.addHandler(forMethod: "GET", path: "/index.html", request: GCDWebServerRequest.self) { [weak self] _ in
            self?.handleWebUI() ?? GCDWebServerErrorResponse(statusCode: 404)
        }

        // GET /api/v1/db/info
        webServer.addHandler(forMethod: "GET", path: "\(apiPrefix)/db/info", request: GCDWebServerRequest.self) { [weak self] request in
            self?.handleDBInfo()
        }

        // GET /api/v1/system/info
        webServer.addHandler(forMethod: "GET", path: "\(apiPrefix)/system/info", request: GCDWebServerRequest.self) { [weak self] _ in
            self?.handleSystemInfo()
        }

        // POST /api/v1/db/sql
        webServer.addHandler(forMethod: "POST", path: "\(apiPrefix)/db/sql", request: GCDWebServerDataRequest.self) { [weak self] request in
            self?.handleExecuteSQL(request: request as! GCDWebServerDataRequest)
        }

        // GET /api/v1/tables
        webServer.addHandler(forMethod: "GET", path: "\(apiPrefix)/tables", request: GCDWebServerRequest.self) { [weak self] request in
            self?.handleListTables()
        }

        // GET /api/v1/tables/:tableName/schema
        webServer.addHandler(forMethod: "GET", pathRegex: "^\(apiPrefix)/tables/([^/]+)/schema$", request: GCDWebServerRequest.self) { [weak self] request in
            self?.handleTableSchema(request: request)
        }

        // GET /api/v1/tables/:tableName/rows
        webServer.addHandler(forMethod: "GET", pathRegex: "^\(apiPrefix)/tables/([^/]+)/rows$", request: GCDWebServerRequest.self) { [weak self] request in
            self?.handleListRows(request: request)
        }

        // POST /api/v1/tables/:tableName/rows
        webServer.addHandler(forMethod: "POST", pathRegex: "^\(apiPrefix)/tables/([^/]+)/rows$", request: GCDWebServerDataRequest.self) { [weak self] request in
            self?.handleCreateRow(request: request as! GCDWebServerDataRequest)
        }

        // PUT /api/v1/tables/:tableName/rows/:rowid
        webServer.addHandler(forMethod: "PUT", pathRegex: "^\(apiPrefix)/tables/([^/]+)/rows/([^/]+)$", request: GCDWebServerDataRequest.self) { [weak self] request in
            self?.handleUpdateRow(request: request as! GCDWebServerDataRequest)
        }

        // DELETE /api/v1/tables/:tableName/rows/:rowid
        webServer.addHandler(forMethod: "DELETE", pathRegex: "^\(apiPrefix)/tables/([^/]+)/rows/([^/]+)$", request: GCDWebServerRequest.self) { [weak self] request in
            self?.handleDeleteRow(request: request)
        }
    }

    private func handleWebUI() -> GCDWebServerResponse? {
        guard let bundlePath = Bundle(for: SQLiteRESTAPIServer.self).path(forResource: "SQLiteREST", ofType: "bundle"),
              let resourceBundle = Bundle(path: bundlePath),
              let htmlPath = resourceBundle.path(forResource: "index", ofType: "html"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: htmlPath)) else {
            return nil
        }
        return GCDWebServerDataResponse(data: data, contentType: "text/html; charset=utf-8")
    }

    private func regexCaptures(from request: GCDWebServerRequest) -> [String]? {
        let key = GCDWebServerRequestAttribute_RegexCaptures
        guard let arr = request.attribute(forKey: key) as? [String] else { return nil }
        return arr
    }

    private func tableName(from request: GCDWebServerRequest) -> String? {
        regexCaptures(from: request)?.first
    }

    private func tableNameAndRowid(from request: GCDWebServerRequest) -> (String, Int64)? {
        guard let caps = regexCaptures(from: request), caps.count >= 2,
              let rowid = Int64(caps[1]) else { return nil }
        return (caps[0], rowid)
    }

    // MARK: - Handlers

    private func handleDBInfo() -> GCDWebServerResponse? {
        do {
            let data = try dbController.getDBInfo()
            return jsonResponse(envelopeSuccess(data: data))
        } catch SQLiteRESTDBError.notOpen {
            return jsonResponse(envelopeError(code: "db_not_open", message: "Database is not open"), statusCode: 503)
        } catch {
            return jsonResponse(envelopeError(code: "sql_error", message: String(describing: error)), statusCode: 500)
        }
    }

    private func handleSystemInfo() -> GCDWebServerResponse? {
        do {
            let database = try dbController.getDatabaseMetadata()
            let device = currentDeviceInfo()
            let app = currentAppInfo()
            let data: [String: Any] = [
                "database": database,
                "device": device,
                "app": app
            ]
            return jsonResponse(envelopeSuccess(data: data))
        } catch SQLiteRESTDBError.notOpen {
            return jsonResponse(envelopeError(code: "db_not_open", message: "Database is not open"), statusCode: 503)
        } catch {
            return jsonResponse(envelopeError(code: "sql_error", message: String(describing: error)), statusCode: 500)
        }
    }

    private func currentDeviceInfo() -> [String: Any] {
        let d = UIDevice.current
        return [
            "name": d.name,
            "model": d.model,
            "localizedModel": d.localizedModel,
            "systemName": d.systemName,
            "systemVersion": d.systemVersion,
            "identifierForVendor": d.identifierForVendor?.uuidString ?? ""
        ]
    }

    private func currentAppInfo() -> [String: Any] {
        let bundle = Bundle.main
        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        let build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
        let bundleID = bundle.bundleIdentifier ?? ""
        return [
            "bundleIdentifier": bundleID,
            "version": version,
            "build": build
        ]
    }

    private func handleExecuteSQL(request: GCDWebServerDataRequest) -> GCDWebServerResponse? {
        guard let json = request.jsonObject as? [String: Any],
              let sql = json["sql"] as? String, !sql.isEmpty else {
            return jsonResponse(envelopeError(code: "bad_request", message: "Missing or invalid 'sql' in body"), statusCode: 400)
        }
        let params = (json["params"] as? [Any]) ?? []
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (type, payload) = try dbController.executeSQL(sql: sql, params: params)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            var data: [String: Any] = ["type": type]
            data.merge(payload) { _, b in b }
            var meta: [String: Any]? = ["executionTime": elapsed]
            if type == "query" { meta = meta ?? [:] }
            return jsonResponse(envelopeSuccess(data: data, meta: meta))
        } catch SQLiteRESTDBError.notOpen {
            return jsonResponse(envelopeError(code: "db_not_open", message: "Database is not open"), statusCode: 503)
        } catch {
            return jsonResponse(envelopeError(code: "sql_error", message: String(describing: error)), statusCode: 400)
        }
    }

    private func handleListTables() -> GCDWebServerResponse? {
        do {
            let data = try dbController.getAllTables()
            return jsonResponse(envelopeSuccess(data: data))
        } catch SQLiteRESTDBError.notOpen {
            return jsonResponse(envelopeError(code: "db_not_open", message: "Database is not open"), statusCode: 503)
        } catch {
            return jsonResponse(envelopeError(code: "sql_error", message: String(describing: error)), statusCode: 500)
        }
    }

    private func handleTableSchema(request: GCDWebServerRequest) -> GCDWebServerResponse? {
        guard let tableName = tableName(from: request), !tableName.isEmpty else {
            return jsonResponse(envelopeError(code: "bad_request", message: "Missing table name"), statusCode: 400)
        }
        do {
            let data = try dbController.getTableSchema(tableName: tableName)
            return jsonResponse(envelopeSuccess(data: data))
        } catch SQLiteRESTDBError.invalidTable(let name) {
            return jsonResponse(envelopeError(code: "invalid_table", message: "Table not found: \(name)"), statusCode: 404)
        } catch SQLiteRESTDBError.notOpen {
            return jsonResponse(envelopeError(code: "db_not_open", message: "Database is not open"), statusCode: 503)
        } catch {
            return jsonResponse(envelopeError(code: "sql_error", message: String(describing: error)), statusCode: 500)
        }
    }

    private func handleListRows(request: GCDWebServerRequest) -> GCDWebServerResponse? {
        guard let tableName = tableName(from: request), !tableName.isEmpty else {
            return jsonResponse(envelopeError(code: "bad_request", message: "Missing table name"), statusCode: 400)
        }
        let query = request.query ?? [:]
        let page = Int(query["_page"] ?? "1") ?? 1
        let perPage = Int(query["_per_page"] ?? "50") ?? 50
        let sort = query["_sort"]
        let order = query["_order"]
        let filterSQL = query["_filter"]
        var columnFilters: [String: String] = [:]
        for (k, v) in query where !k.hasPrefix("_") {
            columnFilters[k] = v
        }
        do {
            let (columns, rows, totalRows) = try dbController.listRows(
                tableName: tableName,
                page: page,
                perPage: perPage,
                sort: sort,
                order: order,
                columnFilters: columnFilters,
                filterSQL: filterSQL
            )
            let meta: [String: Any] = [
                "page": page,
                "per_page": perPage,
                "total_rows": totalRows
            ]
            let data: [String: Any] = [
                "columns": columns,
                "rows": rows
            ]
            return jsonResponse(envelopeSuccess(data: data, meta: meta))
        } catch SQLiteRESTDBError.invalidTable(let name) {
            return jsonResponse(envelopeError(code: "invalid_table", message: "Table not found: \(name)"), statusCode: 404)
        } catch SQLiteRESTDBError.notOpen {
            return jsonResponse(envelopeError(code: "db_not_open", message: "Database is not open"), statusCode: 503)
        } catch {
            return jsonResponse(envelopeError(code: "sql_error", message: String(describing: error)), statusCode: 500)
        }
    }

    private func handleCreateRow(request: GCDWebServerDataRequest) -> GCDWebServerResponse? {
        guard let tableName = tableName(from: request), !tableName.isEmpty else {
            return jsonResponse(envelopeError(code: "bad_request", message: "Missing table name"), statusCode: 400)
        }
        guard let fields = request.jsonObject as? [String: Any], !fields.isEmpty else {
            return jsonResponse(envelopeError(code: "bad_request", message: "Body must be a non-empty JSON object"), statusCode: 400)
        }
        do {
            let rowid = try dbController.createRow(tableName: tableName, fields: fields)
            return jsonResponse(envelopeSuccess(data: ["rowid": rowid]))
        } catch SQLiteRESTDBError.invalidTable(let name) {
            return jsonResponse(envelopeError(code: "invalid_table", message: "Table not found: \(name)"), statusCode: 404)
        } catch SQLiteRESTDBError.notOpen {
            return jsonResponse(envelopeError(code: "db_not_open", message: "Database is not open"), statusCode: 503)
        } catch {
            return jsonResponse(envelopeError(code: "sql_error", message: String(describing: error)), statusCode: 400)
        }
    }

    private func handleUpdateRow(request: GCDWebServerDataRequest) -> GCDWebServerResponse? {
        guard let (tableName, rowid) = tableNameAndRowid(from: request) else {
            return jsonResponse(envelopeError(code: "bad_request", message: "Missing table name or invalid rowid"), statusCode: 400)
        }
        guard let json = request.jsonObject as? [String: Any] else {
            return jsonResponse(envelopeError(code: "bad_request", message: "Body must be a JSON object"), statusCode: 400)
        }
        let fields = json
        do {
            let affected = try dbController.updateRow(tableName: tableName, rowid: rowid, fields: fields)
            return jsonResponse(envelopeSuccess(data: ["rowsAffected": affected]))
        } catch SQLiteRESTDBError.invalidTable(let name) {
            return jsonResponse(envelopeError(code: "invalid_table", message: "Table not found: \(name)"), statusCode: 404)
        } catch SQLiteRESTDBError.notOpen {
            return jsonResponse(envelopeError(code: "db_not_open", message: "Database is not open"), statusCode: 503)
        } catch {
            return jsonResponse(envelopeError(code: "sql_error", message: String(describing: error)), statusCode: 400)
        }
    }

    private func handleDeleteRow(request: GCDWebServerRequest) -> GCDWebServerResponse? {
        guard let (tableName, rowid) = tableNameAndRowid(from: request) else {
            return jsonResponse(envelopeError(code: "bad_request", message: "Missing table name or invalid rowid"), statusCode: 400)
        }
        do {
            let affected = try dbController.deleteRow(tableName: tableName, rowid: rowid)
            return jsonResponse(envelopeSuccess(data: ["rowsAffected": affected]))
        } catch SQLiteRESTDBError.invalidTable(let name) {
            return jsonResponse(envelopeError(code: "invalid_table", message: "Table not found: \(name)"), statusCode: 404)
        } catch SQLiteRESTDBError.notOpen {
            return jsonResponse(envelopeError(code: "db_not_open", message: "Database is not open"), statusCode: 503)
        } catch {
            return jsonResponse(envelopeError(code: "sql_error", message: String(describing: error)), statusCode: 400)
        }
    }
}
