import CryptoKit
import Foundation
import SQLite3

struct ScanLogEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let licenseHash: String
    let ageBracket: String
    let verdict: Verdict
    let timestamp: Date
}

@MainActor
final class ScanLogger {
    static let shared = ScanLogger()

    private var guestSessionEntries: [ScanLogEntry] = []
    private var database: OpaquePointer?

    private init() {
        openDatabase()
        createSchema()
    }

    deinit {
        sqlite3_close(database)
    }

    func record(
        licenseNumber: String?,
        result: VerificationResult,
        retentionHours: Int,
        isAuthenticated: Bool
    ) -> TimeInterval? {
        guard let licenseNumber, !licenseNumber.isEmpty else { return nil }
        let hash = SHA256.hash(data: Data(licenseNumber.uppercased().utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let entry = ScanLogEntry(
            id: UUID(),
            licenseHash: hash,
            ageBracket: (result.age ?? 0) >= 21 ? "OVER" : "UNDER",
            verdict: result.verdict,
            timestamp: .now
        )
        let existing = load(
            retentionHours: retentionHours,
            isAuthenticated: isAuthenticated
        )
        let duplicate = existing
            .filter {
                $0.licenseHash == hash
                    && Date().timeIntervalSince($0.timestamp) <= 600
            }
            .map { Date().timeIntervalSince($0.timestamp) }
            .min()

        if isAuthenticated {
            insert(entry)
        } else {
            guestSessionEntries.append(entry)
        }
        return duplicate
    }

    func load(retentionHours: Int, isAuthenticated: Bool) -> [ScanLogEntry] {
        let cutoff = Date().addingTimeInterval(TimeInterval(-retentionHours * 3600))
        if !isAuthenticated {
            guestSessionEntries.removeAll { $0.timestamp < cutoff }
            return guestSessionEntries
        }

        deleteAuthenticatedEntries(before: cutoff)
        return authenticatedEntries(since: cutoff)
    }

    func clear() {
        guestSessionEntries.removeAll()
        guard let database else { return }
        sqlite3_exec(database, "DELETE FROM scan_history;", nil, nil, nil)
    }

    private func openDatabase() {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }
        try? FileManager.default.createDirectory(
            at: support,
            withIntermediateDirectories: true
        )
        let url = support.appending(path: "scan-history.sqlite3")
        guard sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            sqlite3_close(database)
            database = nil
            return
        }
        sqlite3_exec(database, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(database, "PRAGMA secure_delete=ON;", nil, nil, nil)
    }

    private func createSchema() {
        let sql = """
        CREATE TABLE IF NOT EXISTS scan_history (
            id TEXT PRIMARY KEY NOT NULL,
            license_hash TEXT NOT NULL,
            age_bracket TEXT NOT NULL,
            verdict TEXT NOT NULL,
            timestamp REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS scan_history_timestamp
        ON scan_history(timestamp);
        """
        sqlite3_exec(database, sql, nil, nil, nil)
    }

    private func insert(_ entry: ScanLogEntry) {
        guard let database else { return }
        let sql = """
        INSERT OR IGNORE INTO scan_history
        (id, license_hash, age_bracket, verdict, timestamp)
        VALUES (?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }
        bind(entry.id.uuidString, index: 1, statement: statement)
        bind(entry.licenseHash, index: 2, statement: statement)
        bind(entry.ageBracket, index: 3, statement: statement)
        bind(entry.verdict.rawValue, index: 4, statement: statement)
        sqlite3_bind_double(statement, 5, entry.timestamp.timeIntervalSince1970)
        sqlite3_step(statement)
    }

    private func authenticatedEntries(since cutoff: Date) -> [ScanLogEntry] {
        guard let database else { return [] }
        let sql = """
        SELECT id, license_hash, age_bracket, verdict, timestamp
        FROM scan_history WHERE timestamp >= ? ORDER BY timestamp DESC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)

        var entries: [ScanLogEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = string(statement, column: 0),
                  let id = UUID(uuidString: idText),
                  let hash = string(statement, column: 1),
                  let bracket = string(statement, column: 2),
                  let verdictText = string(statement, column: 3),
                  let verdict = Verdict(rawValue: verdictText) else {
                continue
            }
            entries.append(
                ScanLogEntry(
                    id: id,
                    licenseHash: hash,
                    ageBracket: bracket,
                    verdict: verdict,
                    timestamp: Date(
                        timeIntervalSince1970: sqlite3_column_double(statement, 4)
                    )
                )
            )
        }
        return entries
    }

    private func deleteAuthenticatedEntries(before cutoff: Date) {
        guard let database else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "DELETE FROM scan_history WHERE timestamp < ?;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
        sqlite3_step(statement)
    }

    private func bind(_ value: String, index: Int32, statement: OpaquePointer?) {
        sqlite3_bind_text(
            statement,
            index,
            value,
            -1,
            unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        )
    }

    private func string(_ statement: OpaquePointer?, column: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }
}
