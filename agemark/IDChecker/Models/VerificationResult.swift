import Foundation

enum Verdict: String, Codable, Sendable {
    case over21 = "OVER 21"
    case under21 = "UNDER 21"
    case expired = "EXPIRED"
    case checkManually = "CHECK MANUALLY"
}

struct VerificationResult: Equatable, Sendable {
    let verdict: Verdict
    let age: Int?
    let reasons: [String]
    let turnsThresholdOn: Date?
    let daysUntilThreshold: Int?
}
