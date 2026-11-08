import Foundation
import UIKit

enum FieldMatch: String, Equatable, Sendable {
    case match = "MATCH"
    case mismatch = "MISMATCH"
    case unclear = "UNCLEAR"
}

struct OCRData: Equatable, Sendable {
    var name: String?
    var dateOfBirth: Date?
    var expirationDate: Date?
    var licenseNumber: String?
    var confidence: [String: Float] = [:]
}

struct ComparisonResult: Equatable, Sendable {
    var name: FieldMatch
    var dateOfBirth: FieldMatch
    var licenseNumber: FieldMatch
    var expirationDate: FieldMatch

    var hasMismatch: Bool {
        [dateOfBirth, expirationDate].contains(.mismatch)
    }

    static let allMatch = ComparisonResult(name: .match, dateOfBirth: .match, licenseNumber: .match, expirationDate: .match)
}

struct ScanResult: Identifiable {
    let id = UUID()
    var barcode: AAMVAData
    var verification: VerificationResult
    var ocr: OCRData?
    var comparison: ComparisonResult?
    var frontImage: UIImage?
    var startedAt: Date
    var isManual: Bool = false
}
