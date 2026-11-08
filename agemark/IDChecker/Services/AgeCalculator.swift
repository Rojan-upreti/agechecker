import Foundation

enum AgeCalculator {
    static func age(on date: Date, born dateOfBirth: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.year], from: dateOfBirth, to: date).year ?? 0
    }

    static func verify(_ data: AAMVAData, on today: Date = .now, threshold: Int = 21, calendar: Calendar = .current) -> VerificationResult {
        guard let dob = data.dateOfBirth, let expiry = data.expirationDate else {
            return VerificationResult(verdict: .checkManually, age: nil, reasons: ["DOB or expiry is missing"], turnsThresholdOn: nil, daysUntilThreshold: nil)
        }
        let age = age(on: today, born: dob, calendar: calendar)
        var reasons: [String] = []

        if dob > today { reasons.append("DOB is in the future") }
        if let issue = data.issueDate {
            if issue > expiry { reasons.append("Issue date is after expiry") }
            if self.age(on: issue, born: dob, calendar: calendar) < 16 { reasons.append("Age at issue is under 16") }
            let validity = calendar.dateComponents([.year], from: issue, to: expiry).year ?? 0
            if !(4...8).contains(validity) { reasons.append("ID validity is outside 4–8 years") }
        }
        let thresholdDate = calendar.date(byAdding: .year, value: threshold, to: dob)
        if let stated = data.under21Until,
           let expected = calendar.date(byAdding: .year, value: 21, to: dob),
           !calendar.isDate(stated, inSameDayAs: expected) {
            reasons.append("Under-21 date does not match DOB")
        }
        if let license = data.licenseNumber, !validLicense(license, state: data.state) {
            reasons.append("License number format is unusual")
        }
        if !reasons.isEmpty {
            return VerificationResult(verdict: .checkManually, age: age, reasons: reasons, turnsThresholdOn: thresholdDate, daysUntilThreshold: nil)
        }
        if today > expiry {
            return VerificationResult(verdict: .expired, age: age, reasons: ["Expired"], turnsThresholdOn: thresholdDate, daysUntilThreshold: nil)
        }
        if age >= threshold {
            return VerificationResult(verdict: .over21, age: age, reasons: [], turnsThresholdOn: thresholdDate, daysUntilThreshold: nil)
        }
        let days = thresholdDate.map { max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: $0)).day ?? 0) }
        return VerificationResult(verdict: .under21, age: age, reasons: [], turnsThresholdOn: thresholdDate, daysUntilThreshold: days)
    }

    private static func validLicense(_ value: String, state: String?) -> Bool {
        let compact = value.replacingOccurrences(of: " ", with: "")
        guard (4...20).contains(compact.count) else { return false }
        return compact.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }
}
