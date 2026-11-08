import Foundation

enum AAMVAParser {
    private static let fieldCodes = [
        "DAQ", "DCS", "DCT", "DAC", "DAD", "DBB", "DBA", "DBD", "DDJ",
        "DAG", "DAI", "DAJ", "DAK", "DAU", "DAY", "DCG"
    ]

    static func parse(_ raw: String) -> AAMVAData {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var values: [String: String] = [:]

        for code in fieldCodes {
            let escapedCodes = fieldCodes.joined(separator: "|")
            let pattern = "(?s)\(code)(.*?)(?=\n|\r|\(escapedCodes)|$)"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
                  let valueRange = Range(match.range(at: 1), in: normalized) else { continue }
            let value = normalized[valueRange].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { values[code] = value }
        }

        return AAMVAData(
            licenseNumber: values["DAQ"],
            lastName: values["DCS"],
            firstName: values["DCT"] ?? values["DAC"],
            middleName: values["DAD"],
            dateOfBirth: date(values["DBB"]),
            expirationDate: date(values["DBA"]),
            issueDate: date(values["DBD"]),
            under21Until: date(values["DDJ"]),
            street: values["DAG"],
            city: values["DAI"],
            state: values["DAJ"],
            postalCode: values["DAK"],
            height: values["DAU"],
            eyeColor: values["DAY"],
            country: values["DCG"]
        )
    }

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let digits = value.filter(\.isNumber)
        guard digits.count >= 8 else { return nil }
        let dateString = String(digits.prefix(8))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let month = Int(dateString.prefix(2)),
              let day = Int(dateString.dropFirst(2).prefix(2)),
              let year = Int(dateString.suffix(4)) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
