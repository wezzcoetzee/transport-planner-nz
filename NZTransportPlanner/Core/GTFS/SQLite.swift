import Foundation
import SQLite3

struct SQLiteError: Error, CustomStringConvertible {
    let message: String
    var description: String { "SQLite: \(message)" }
}

/// Thin wrapper over the C API. Not thread-safe; owned by the `GTFSStore` actor.
final class SQLiteConnection {
    private var db: OpaquePointer?

    init(path: String, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        guard sqlite3_open_v2(path, &db, flags | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            throw SQLiteError(message: String(cString: sqlite3_errmsg(db)))
        }
    }

    deinit { sqlite3_close_v2(db) }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw SQLiteError(message: msg)
        }
    }

    func prepare(_ sql: String) throws -> Statement {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw SQLiteError(message: String(cString: sqlite3_errmsg(db)))
        }
        return Statement(stmt)
    }

    /// Runs a query and maps each row.
    func query<T>(_ sql: String, bind: [SQLiteBindable] = [], map: (Statement) throws -> T) throws -> [T] {
        let stmt = try prepare(sql)
        for (i, v) in bind.enumerated() { v.bind(to: stmt, index: Int32(i + 1)) }
        var out: [T] = []
        while try stmt.step() { out.append(try map(stmt)) }
        return out
    }

    final class Statement {
        let raw: OpaquePointer
        init(_ raw: OpaquePointer) { self.raw = raw }
        deinit { sqlite3_finalize(raw) }

        func reset() { sqlite3_reset(raw); sqlite3_clear_bindings(raw) }

        /// Returns true while rows remain.
        func step() throws -> Bool {
            switch sqlite3_step(raw) {
            case SQLITE_ROW: return true
            case SQLITE_DONE: return false
            default: throw SQLiteError(message: String(cString: sqlite3_errmsg(sqlite3_db_handle(raw))))
            }
        }

        func bind(_ values: SQLiteBindable...) { for (i, v) in values.enumerated() { v.bind(to: self, index: Int32(i + 1)) } }

        func text(_ col: Int32) -> String { sqlite3_column_text(raw, col).map { String(cString: $0) } ?? "" }
        func int(_ col: Int32) -> Int { Int(sqlite3_column_int64(raw, col)) }
        func double(_ col: Int32) -> Double { sqlite3_column_double(raw, col) }
        func isNull(_ col: Int32) -> Bool { sqlite3_column_type(raw, col) == SQLITE_NULL }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

protocol SQLiteBindable { func bind(to stmt: SQLiteConnection.Statement, index: Int32) }
extension String: SQLiteBindable { func bind(to stmt: SQLiteConnection.Statement, index: Int32) { sqlite3_bind_text(stmt.raw, index, self, -1, SQLITE_TRANSIENT) } }
extension Substring: SQLiteBindable { func bind(to stmt: SQLiteConnection.Statement, index: Int32) { String(self).bind(to: stmt, index: index) } }
extension Int: SQLiteBindable { func bind(to stmt: SQLiteConnection.Statement, index: Int32) { sqlite3_bind_int64(stmt.raw, index, Int64(self)) } }
extension Double: SQLiteBindable { func bind(to stmt: SQLiteConnection.Statement, index: Int32) { sqlite3_bind_double(stmt.raw, index, self) } }
extension Optional: SQLiteBindable where Wrapped: SQLiteBindable {
    func bind(to stmt: SQLiteConnection.Statement, index: Int32) {
        if let self { self.bind(to: stmt, index: index) } else { sqlite3_bind_null(stmt.raw, index) }
    }
}

/// Builds "?,?,?" for IN clauses.
func sqlPlaceholders(_ count: Int) -> String { Array(repeating: "?", count: count).joined(separator: ",") }
