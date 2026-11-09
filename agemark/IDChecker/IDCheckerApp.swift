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
    case home, front, back, verdict, manual, settings, paywall, signIn, account, guestScanLimit
    case premiumIntroduction, premiumDocumentReview, faceCapture, premiumResult
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
    let authentication = AuthenticationManager()
    let scanUsage = ScanUsageManager()
    var requestedAuthenticatedAction: RequestedAuthenticatedAction = .accountManagement
    private var activeScanWorkflowID: UUID?
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
    var verificationTier: VerificationTier = .base
    var premiumSession = VerificationSession.local()
    var premiumEvidence = PremiumVerificationEvidence()
    var premiumDecision: PremiumVerificationDecision?
    var idPortrait: UIImage?
    var isPreparingPortrait = false
    var premiumPreparationError: String?

    func beginScan(tier: VerificationTier = .base) {
        verificationTier = tier

        if tier == .premium {
            guard authentication.isAuthenticated else {
                requestedAuthenticatedAction = .premiumVerification
                screen = .signIn
                return
            }
            guard FeatureAccessManager.premiumEntitlement(from: store) == .entitled else {
                screen = .paywall
                return
            }
        }

        guard let workflowID = scanUsage.beginWorkflow(
            isAuthenticated: authentication.isAuthenticated
        ) else {
            requestedAuthenticatedAction = .regularScan
            screen = .guestScanLimit
            return
        }
        activeScanWorkflowID = workflowID

        if tier == .premium {
            premiumSession = .local()
            premiumEvidence = PremiumVerificationEvidence()
            premiumDecision = nil
            idPortrait = nil
            premiumPreparationError = nil
            screen = .premiumIntroduction
            return
        }

        prepareDocumentScan()
    }

    func requestAuthentication(for action: RequestedAuthenticatedAction) {
        requestedAuthenticatedAction = action
        screen = .signIn
    }

    func authenticationCompleted() {
        guard authentication.isAuthenticated else { return }
        let action = requestedAuthenticatedAction
        if action == .premiumVerification {
            Task {
                await store.refreshEntitlements()
                beginScan(tier: .premium)
            }
            return
        }
        switch action {
        case .regularScan:
            beginScan(tier: .base)
        case .accountManagement:
            screen = .account
        case .premiumVerification:
            break
        }
    }

    func cancelAuthentication() {
        authentication.cancelSignIn()
        screen = .home
    }

    func cancelScan() {
        scanUsage.cancelWorkflow(id: activeScanWorkflowID)
        activeScanWorkflowID = nil
        verificationTier = .base
        screen = .home
    }

    private func prepareDocumentScan() {
        startedAt = .now
        frontImage = nil
        ocrData = nil
        scanResult = nil
        screen = fastMode ? .back : .front
    }

    func confirmPremiumConsent() {
        startedAt = .now
        frontImage = nil
        ocrData = nil
        scanResult = nil
        screen = .front
    }

    func frontCaptured(_ image: UIImage) {
        frontImage = image
        if verificationTier == .premium {
            premiumEvidence.frontDocument = .passed
        }
        screen = .back
        Task {
            let value = try? await FrontOCRService.recognize(image: image)
            ocrData = value
            updateComparison()
        }
    }

    func barcodeCaptured(_ raw: String) {
        guard let workflowID = activeScanWorkflowID else { return }
        activeScanWorkflowID = nil
        let data = AAMVAParser.parse(raw)
        let verification = AgeCalculator.verify(data, threshold: threshold)
        scanResult = ScanResult(barcode: data, verification: verification, ocr: ocrData, comparison: compare(ocrData, data), frontImage: frontImage, startedAt: startedAt)
        scanCount += 1
        scanUsage.completeWorkflow(id: workflowID)
        if let seconds = ScanLogger.shared.record(licenseNumber: data.licenseNumber, result: verification, retentionHours: logRetentionHours, isAuthenticated: authentication.isAuthenticated) {
            duplicateMessage = "Already scanned \(max(1, Int(seconds / 60))) min ago — pass-back?"
        } else {
            duplicateMessage = nil
        }
        if verificationTier == .premium {
            premiumEvidence.backDocument = .passed
            premiumEvidence.documentConsistency = scanResult?.comparison?.hasMismatch == true
                ? .failed(reason: "Front and back document details conflict")
                : .passed
            preparePremiumPortrait()
            screen = .premiumDocumentReview
        } else {
            screen = .verdict
            feedback(for: verification.verdict)
        }
    }

    func showFaceCapture() {
        guard idPortrait != nil else { return }
        screen = .faceCapture
    }

    func finishPremium(_ decision: PremiumVerificationDecision) {
        premiumDecision = decision
        screen = .premiumResult
    }

    func cancelPremium() {
        scanUsage.cancelWorkflow(id: activeScanWorkflowID)
        activeScanWorkflowID = nil
        verificationTier = .base
        frontImage = nil
        idPortrait = nil
        ocrData = nil
        scanResult = nil
        premiumDecision = nil
        screen = .home
    }

    private func preparePremiumPortrait() {
        guard let frontImage else {
            premiumEvidence.portraitExtraction = .inconclusive(reason: "Front ID image is missing")
            premiumPreparationError = "The ID front must be captured again."
            return
        }
        isPreparingPortrait = true
        premiumPreparationError = nil
        Task {
            do {
                idPortrait = try await IDPortraitExtractor.extract(from: frontImage)
                premiumEvidence.portraitExtraction = .passed
            } catch {
                premiumEvidence.portraitExtraction = .inconclusive(reason: error.localizedDescription)
                premiumPreparationError = "No clear portrait was found. Retake the ID front."
            }
            isPreparingPortrait = false
        }
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

    func pasteBarcode(_ raw: String) {
        guard let workflowID = scanUsage.beginWorkflow(
            isAuthenticated: authentication.isAuthenticated
        ) else {
            requestedAuthenticatedAction = .regularScan
            screen = .guestScanLimit
            return
        }
        activeScanWorkflowID = workflowID
        startedAt = .now
        barcodeCaptured(raw)
    }

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
