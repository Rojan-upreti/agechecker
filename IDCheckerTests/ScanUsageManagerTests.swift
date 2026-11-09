import Foundation
import Testing
@testable import IDChecker

@MainActor
struct ScanUsageManagerTests {
    @Test
    func guestCanCompleteFiveAndSixthIsBlocked() throws {
        let store = MemoryScanUsageStore()
        let clock = TestClock(date: utcDate(year: 2026, month: 11, day: 9))
        let manager = ScanUsageManager(store: store, now: { clock.date })

        for expectedRemaining in stride(from: 4, through: 0, by: -1) {
            let workflow = try #require(manager.beginWorkflow(isAuthenticated: false))
            #expect(manager.completeWorkflow(id: workflow))
            #expect(manager.remainingToday == expectedRemaining)
        }

        #expect(manager.beginWorkflow(isAuthenticated: false) == nil)
        #expect(manager.completedToday == 5)
    }

    @Test
    func allowanceResetsAtUTCDateBoundary() throws {
        let store = MemoryScanUsageStore()
        let clock = TestClock(date: utcDate(year: 2026, month: 11, day: 9, hour: 23, minute: 59))
        let manager = ScanUsageManager(store: store, now: { clock.date })

        let workflow = try #require(manager.beginWorkflow(isAuthenticated: false))
        manager.completeWorkflow(id: workflow)
        #expect(manager.remainingToday == 4)

        clock.date = utcDate(year: 2026, month: 11, day: 10)
        manager.refresh()
        #expect(manager.remainingToday == 5)
        #expect(manager.completedToday == 0)
    }

    @Test
    func countPersistsAcrossManagerRestoration() throws {
        let store = MemoryScanUsageStore()
        let date = utcDate(year: 2026, month: 11, day: 9)
        let first = ScanUsageManager(store: store, now: { date })
        let workflow = try #require(first.beginWorkflow(isAuthenticated: false))
        first.completeWorkflow(id: workflow)

        let restored = ScanUsageManager(store: store, now: { date })
        #expect(restored.completedToday == 1)
        #expect(restored.remainingToday == 4)
    }

    @Test
    func cancellationAndDuplicateCompletionDoNotConsumeExtraScans() throws {
        let store = MemoryScanUsageStore()
        let date = utcDate(year: 2026, month: 11, day: 9)
        let manager = ScanUsageManager(store: store, now: { date })

        let cancelled = try #require(manager.beginWorkflow(isAuthenticated: false))
        manager.cancelWorkflow(id: cancelled)
        #expect(manager.remainingToday == 5)

        let completed = try #require(manager.beginWorkflow(isAuthenticated: false))
        #expect(manager.completeWorkflow(id: completed))
        #expect(!manager.completeWorkflow(id: completed))
        #expect(manager.completedToday == 1)
    }

    @Test
    func signedInWorkflowDoesNotUseGuestAllowance() throws {
        let store = MemoryScanUsageStore()
        let date = utcDate(year: 2026, month: 11, day: 9)
        let manager = ScanUsageManager(store: store, now: { date })

        let workflow = try #require(manager.beginWorkflow(isAuthenticated: true))
        #expect(manager.completeWorkflow(id: workflow))
        #expect(manager.remainingToday == 5)
    }

    @Test
    func authenticationDoesNotGrantPremiumEntitlement() {
        #expect(
            FeatureAccessManager.state(
                isAuthenticated: true,
                entitlement: .notEntitled
            ) == .authenticatedWithoutPremium
        )
        #expect(
            FeatureAccessManager.state(
                isAuthenticated: false,
                entitlement: .entitled
            ) == .guest
        )
    }
}

private final class MemoryScanUsageStore: ScanUsagePersisting {
    var record: GuestScanUsageRecord?
    let installationID = "test-installation"

    func load() -> GuestScanUsageRecord? {
        record
    }

    func save(_ record: GuestScanUsageRecord) {
        self.record = record
    }
}

private final class TestClock {
    var date: Date

    init(date: Date) {
        self.date = date
    }
}

private func utcDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int = 0,
    minute: Int = 0
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar.date(
        from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
    ) ?? .distantPast
}
