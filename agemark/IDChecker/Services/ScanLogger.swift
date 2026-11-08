import CryptoKit
import Foundation

struct ScanLogEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let licenseHash: String
    let ageBracket: String
    let verdict: Verdict
    let timestamp: Date
}

final class ScanLogger {
    static let shared = ScanLogger()
    private let key = "privacyScanLog"

    func record(licenseNumber: String?, result: VerificationResult, retentionHours: Int) -> TimeInterval? {
        guard let licenseNumber, !licenseNumber.isEmpty else { return nil }
        let hash = SHA256.hash(data: Data(licenseNumber.uppercased().utf8)).map { String(format: "%02x", $0) }.joined()
        var entries = load(retentionHours: retentionHours)
        let duplicate = entries.filter { $0.licenseHash == hash && Date().timeIntervalSince($0.timestamp) <= 600 }.map { Date().timeIntervalSince($0.timestamp) }.min()
        entries.append(ScanLogEntry(id: UUID(), licenseHash: hash, ageBracket: (result.age ?? 0) >= 21 ? "OVER" : "UNDER", verdict: result.verdict, timestamp: .now))
        save(entries)
        return duplicate
    }

    func load(retentionHours: Int) -> [ScanLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([ScanLogEntry].self, from: data) else { return [] }
        let cutoff = Date().addingTimeInterval(TimeInterval(-retentionHours * 3600))
        let retained = entries.filter { $0.timestamp >= cutoff }
        if retained.count != entries.count { save(retained) }
        return retained
    }

    func clear() { UserDefaults.standard.removeObject(forKey: key) }

    private func save(_ entries: [ScanLogEntry]) {
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: key) }
    }
}
