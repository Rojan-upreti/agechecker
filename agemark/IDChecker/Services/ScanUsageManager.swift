import Foundation
import Observation
import Security

protocol ScanUsagePersisting: AnyObject {
    func load() -> GuestScanUsageRecord?
    func save(_ record: GuestScanUsageRecord)
    var installationID: String { get }
}

struct GuestScanUsageRecord: Codable, Equatable, Sendable {
    var utcDay: Int
    var completedWorkflowIDs: Set<UUID>
    var installationID: String

    var completedCount: Int {
        completedWorkflowIDs.count
    }
}

@MainActor
@Observable
final class ScanUsageManager {
    static let dailyGuestLimit = 5

    private(set) var completedToday = 0
    private(set) var remainingToday = dailyGuestLimit

    private let store: any ScanUsagePersisting
    private let now: () -> Date
    private var record: GuestScanUsageRecord
    private var activeWorkflows: [UUID: Bool] = [:]

    convenience init() {
        self.init(store: LocalScanUsageStore(), now: Date.init)
    }

    init(store: any ScanUsagePersisting, now: @escaping () -> Date) {
        self.store = store
        self.now = now
        let today = Self.utcDay(for: now())
        let stored = store.load()
        if let stored, stored.utcDay >= today {
            record = stored
        } else {
            record = GuestScanUsageRecord(
                utcDay: today,
                completedWorkflowIDs: [],
                installationID: store.installationID
            )
            store.save(record)
        }
        publish()
    }

    var canBeginGuestScan: Bool {
        refreshDayIfNeeded()
        return remainingToday > 0 && activeWorkflows.values.filter { $0 }.count < remainingToday
    }

    func beginWorkflow(isAuthenticated: Bool) -> UUID? {
        refreshDayIfNeeded()
        if !isAuthenticated && !canBeginGuestScan {
            return nil
        }
        let id = UUID()
        activeWorkflows[id] = !isAuthenticated
        return id
    }

    @discardableResult
    func completeWorkflow(id: UUID) -> Bool {
        refreshDayIfNeeded()
        guard let countsAgainstGuestLimit = activeWorkflows.removeValue(forKey: id) else {
            return false
        }
        guard countsAgainstGuestLimit else { return true }
        guard !record.completedWorkflowIDs.contains(id),
              record.completedCount < Self.dailyGuestLimit else {
            return false
        }
        record.completedWorkflowIDs.insert(id)
        persistAndPublish()
        return true
    }

    func cancelWorkflow(id: UUID?) {
        guard let id else { return }
        activeWorkflows.removeValue(forKey: id)
    }

    func refresh() {
        refreshDayIfNeeded()
    }

    static func utcDay(for date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return (components.year ?? 0) * 10_000
            + (components.month ?? 0) * 100
            + (components.day ?? 0)
    }

    private func refreshDayIfNeeded() {
        let today = Self.utcDay(for: now())
        guard today > record.utcDay else {
            publish()
            return
        }
        record = GuestScanUsageRecord(
            utcDay: today,
            completedWorkflowIDs: [],
            installationID: store.installationID
        )
        activeWorkflows.removeAll()
        persistAndPublish()
    }

    private func persistAndPublish() {
        store.save(record)
        publish()
    }

    private func publish() {
        completedToday = min(record.completedCount, Self.dailyGuestLimit)
        remainingToday = max(0, Self.dailyGuestLimit - completedToday)
    }
}

final class LocalScanUsageStore: ScanUsagePersisting {
    private let defaults: UserDefaults
    private let recordKey = "guestScanUsage.v1"
    private let fallbackInstallationKey = "guestInstallationID.v1"
    private let keychainService = "net.taxcurb.idchecker.usage"
    private let keychainAccount = "installation-id"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var installationID: String {
        if let existing = keychainInstallationID() {
            return existing
        }
        let identifier = defaults.string(forKey: fallbackInstallationKey) ?? UUID().uuidString
        defaults.set(identifier, forKey: fallbackInstallationKey)
        saveInstallationIDToKeychain(identifier)
        return identifier
    }

    func load() -> GuestScanUsageRecord? {
        guard let data = defaults.data(forKey: recordKey) else { return nil }
        return try? JSONDecoder().decode(GuestScanUsageRecord.self, from: data)
    }

    func save(_ record: GuestScanUsageRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: recordKey)
    }

    private func keychainInstallationID() -> String? {
        var query = baseKeychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func saveInstallationIDToKeychain(_ identifier: String) {
        guard let data = identifier.data(using: .utf8) else { return }
        var item = baseKeychainQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemDelete(baseKeychainQuery as CFDictionary)
        SecItemAdd(item as CFDictionary, nil)
    }

    private var baseKeychainQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
    }
}
