import AudioToolbox
import Observation
import SwiftUI
import UIKit

@main
struct IDCheckerApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

enum AppScreen: Equatable {
    case home, front, back, verdict, manual, settings, paywall
}

enum AppTheme: String, CaseIterable, Identifiable {
    case day
    case night

    var id: Self { self }

    var colorScheme: ColorScheme {
        switch self {
        case .day: .light
        case .night: .dark
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var screen: AppScreen = .home
    let store = StoreManager()
    var scanResult: ScanResult?
    var frontImage: UIImage?
    var ocrData: OCRData?
    var startedAt = Date()
    var threshold = 21
    var fastMode = false
    var theme = AppTheme(
        rawValue: UserDefaults.standard.string(forKey: "preferredAppTheme") ?? ""
    ) ?? .night
    var soundEnabled = true
    var hapticEnabled = true
    var scanCount = 0
    var logRetentionHours = 168
    var duplicateMessage: String?

    func beginScan() {
        guard scanCount < 10 || store.isSubscribed else {
            screen = .paywall
            return
        }
        startedAt = .now
        frontImage = nil
        ocrData = nil
        scanResult = nil
        screen = fastMode ? .back : .front
    }

    func frontCaptured(_ image: UIImage) {
        frontImage = image
        screen = .back
        Task {
            let value = try? await FrontOCRService.recognize(image: image)
            ocrData = value
            updateComparison()
        }
    }

    func barcodeCaptured(_ raw: String) {
        let data = AAMVAParser.parse(raw)
        let verification = AgeCalculator.verify(data, threshold: threshold)
        scanResult = ScanResult(barcode: data, verification: verification, ocr: ocrData, comparison: compare(ocrData, data), frontImage: frontImage, startedAt: startedAt)
        scanCount += 1
        if let seconds = ScanLogger.shared.record(licenseNumber: data.licenseNumber, result: verification, retentionHours: logRetentionHours) {
            duplicateMessage = "Already scanned \(max(1, Int(seconds / 60))) min ago — pass-back?"
        } else {
            duplicateMessage = nil
        }
        screen = .verdict
        feedback(for: verification.verdict)
    }

    func loadTest() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dob = calendar.date(from: DateComponents(year: 1990, month: 1, day: 1))!
        let expiry = calendar.date(from: DateComponents(year: 2030, month: 1, day: 1))!
        let data = AAMVAData(licenseNumber: "TEST19900101", lastName: "TEST", firstName: "JOHN", dateOfBirth: dob, expirationDate: expiry)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7))!
        let verification = AgeCalculator.verify(data, on: reference, threshold: threshold, calendar: calendar)
        let ocr = OCRData(name: "JOHN TEST", dateOfBirth: dob, expirationDate: expiry, licenseNumber: "TEST19900101")
        scanResult = ScanResult(barcode: data, verification: verification, ocr: ocr, comparison: .allMatch, startedAt: .now)
        screen = .verdict
    }

    func submitManual(name: String, dob: Date, expiry: Date, license: String) {
        let parts = name.split(separator: " ")
        let data = AAMVAData(licenseNumber: license, lastName: parts.last.map(String.init), firstName: parts.first.map(String.init), dateOfBirth: dob, expirationDate: expiry)
        scanResult = ScanResult(barcode: data, verification: AgeCalculator.verify(data, threshold: threshold), startedAt: .now, isManual: true)
        screen = .verdict
    }

    func pasteBarcode(_ raw: String) { startedAt = .now; barcodeCaptured(raw) }

    private func updateComparison() {
        guard var result = scanResult else { return }
        result.ocr = ocrData
        result.comparison = compare(ocrData, result.barcode)
        if result.comparison?.hasMismatch == true {
            let fields = mismatchNames(result.comparison!)
            result.verification = VerificationResult(verdict: .checkManually, age: result.verification.age, reasons: ["Front/back mismatch: " + fields.joined(separator: ", ")], turnsThresholdOn: result.verification.turnsThresholdOn, daysUntilThreshold: result.verification.daysUntilThreshold)
        }
        scanResult = result
    }

    private func compare(_ ocr: OCRData?, _ barcode: AAMVAData) -> ComparisonResult? {
        guard let ocr else { return nil }
        func value<T: Equatable>(_ front: T?, _ back: T?) -> FieldMatch {
            guard let front, let back else { return .unclear }
            return front == back ? .match : .mismatch
        }
        return ComparisonResult(
            name: .unclear,
            dateOfBirth: value(ocr.dateOfBirth, barcode.dateOfBirth),
            licenseNumber: .unclear,
            expirationDate: value(ocr.expirationDate, barcode.expirationDate)
        )
    }

    private func mismatchNames(_ comparison: ComparisonResult) -> [String] {
        [("DOB", comparison.dateOfBirth), ("Expiry", comparison.expirationDate)]
            .compactMap { $0.1 == .mismatch ? $0.0 : nil }
    }

    private func feedback(for verdict: Verdict) {
        if hapticEnabled {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(verdict == .over21 ? .success : .error)
        }
        if soundEnabled { AudioServicesPlaySystemSound(1104) }
    }
}
