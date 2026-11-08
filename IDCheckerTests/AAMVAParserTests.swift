import Foundation
import Testing
@testable import IDChecker

struct AAMVAParserTests {
    @Test func parsesRequiredSample() throws {
        let raw = "@\nANSI 636000090102DL00410288ZN03190024DLDAQTEST19900101\nDCSDOE\nDCTJOHN\nDADTEST\nDBB01011990\nDBA01012030\nDBD01012022\nDDJ01012011\nDAU064 IN\nDAG123 TEST ST\nDAICITY\nDAJXX\nDAK12345"
        let data = AAMVAParser.parse(raw)
        #expect(data.firstName == "JOHN")
        #expect(data.lastName == "DOE")
        #expect(data.licenseNumber == "TEST19900101")
        let calendar = Calendar(identifier: .gregorian)
        #expect(calendar.dateComponents([.year, .month, .day], from: try #require(data.dateOfBirth)) == DateComponents(year: 1990, month: 1, day: 1))
        #expect(calendar.dateComponents([.year, .month, .day], from: try #require(data.expirationDate)) == DateComponents(year: 2030, month: 1, day: 1))
        #expect(data.middleName == "TEST")
        #expect(data.street == "123 TEST ST")
        #expect(data.city == "CITY")
        #expect(data.state == "XX")
        #expect(data.postalCode == "12345")
        #expect(data.height == "064 IN")
    }
}
