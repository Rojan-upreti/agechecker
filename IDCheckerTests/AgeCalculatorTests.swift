import Foundation
import Testing
@testable import IDChecker

struct AgeCalculatorTests {
    @Test func johnTestIs36AndOver21() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dob = try #require(calendar.date(from: DateComponents(year: 1990, month: 1, day: 1)))
        let expiry = try #require(calendar.date(from: DateComponents(year: 2030, month: 1, day: 1)))
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 7)))
        let data = AAMVAData(licenseNumber: "TEST19900101", lastName: "TEST", firstName: "JOHN", dateOfBirth: dob, expirationDate: expiry)
        let result = AgeCalculator.verify(data, on: today, threshold: 21, calendar: calendar)
        #expect(result.age == 36)
        #expect(result.verdict == .over21)
    }

    @Test func expirationOverridesAge() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dob = try #require(calendar.date(from: DateComponents(year: 1990, month: 1, day: 1)))
        let expiry = try #require(calendar.date(from: DateComponents(year: 2020, month: 1, day: 1)))
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 7)))
        let result = AgeCalculator.verify(AAMVAData(dateOfBirth: dob, expirationDate: expiry), on: today, calendar: calendar)
        #expect(result.verdict == .expired)
    }
}
