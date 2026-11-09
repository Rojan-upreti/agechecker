import Foundation
import UIKit

enum VerificationTier: String, CaseIterable, Identifiable, Sendable {
    case base
    case premium

    var id: Self { self }
}

enum PremiumVerificationOutcome: String, Equatable, Sendable {
    case verified
    case retryRequired
    case manualReviewRequired
    case verificationUnavailable
    case rejected
}

enum EvidenceStatus: Equatable, Sendable {
    case passed
    case failed(reason: String)
    case inconclusive(reason: String)
    case unavailable(reason: String)

    var passed: Bool {
        if case .passed = self { return true }
        return false
    }
}

struct FaceMatchResult: Equatable, Sendable {
    let status: EvidenceStatus
    let similarity: Float?
    let modelIdentifier: String?
    let thresholdVersion: String?
}

struct LivenessResult: Equatable, Sendable {
    let status: EvidenceStatus
    let providerIdentifier: String?
    let activeChallengePassed: Bool
}

struct CameraIntegrityResult: Equatable, Sendable {
    let status: EvidenceStatus
    let interruptionCount: Int
}

struct PremiumVerificationEvidence: Equatable, Sendable {
    var frontDocument: EvidenceStatus = .inconclusive(reason: "Front of ID not captured")
    var backDocument: EvidenceStatus = .inconclusive(reason: "Back of ID not captured")
    var documentConsistency: EvidenceStatus = .inconclusive(reason: "Document consistency not checked")
    var portraitExtraction: EvidenceStatus = .inconclusive(reason: "ID portrait not extracted")
    var liveCaptureQuality: EvidenceStatus = .inconclusive(reason: "Face capture not completed")
    var faceMatch = FaceMatchResult(
        status: .unavailable(reason: "No licensed face-embedding model is installed"),
        similarity: nil,
        modelIdentifier: nil,
        thresholdVersion: nil
    )
    var liveness = LivenessResult(
        status: .unavailable(reason: "No validated presentation-attack model or SDK is installed"),
        providerIdentifier: nil,
        activeChallengePassed: false
    )
    var cameraIntegrity = CameraIntegrityResult(
        status: .inconclusive(reason: "Camera session not evaluated"),
        interruptionCount: 0
    )
}

struct PremiumVerificationDecision: Equatable, Sendable {
    let outcome: PremiumVerificationOutcome
    let reasons: [String]
    let policyVersion: String
    let clientIsAuthoritative: Bool
}

struct VerificationSession: Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let expiresAt: Date
    let challengeNonce: Data?
    let serverIssued: Bool
    var attempt: Int

    static func local(expiresAfter seconds: TimeInterval = 300) -> VerificationSession {
        let now = Date()
        return VerificationSession(
            id: UUID(),
            createdAt: now,
            expiresAt: now.addingTimeInterval(seconds),
            challengeNonce: nil,
            serverIssued: false,
            attempt: 1
        )
    }
}

struct PremiumCaptureBundle: @unchecked Sendable {
    let portrait: UIImage
    let liveFrames: [UIImage]
    let activeChallengePassed: Bool
    let interruptionCount: Int
}

enum VerificationDecisionEngine {
    static let policyVersion = "premium-local-1"

    static func evaluate(_ evidence: PremiumVerificationEvidence, session: VerificationSession) -> PremiumVerificationDecision {
        var reasons: [String] = []

        guard session.expiresAt > Date() else {
            return decision(.retryRequired, ["Verification session expired"])
        }
        guard session.serverIssued else {
            reasons.append("No server-issued challenge or authoritative backend decision is available")
            return decision(.verificationUnavailable, reasons)
        }

        let mandatory: [(String, EvidenceStatus)] = [
            ("Front ID", evidence.frontDocument),
            ("Back ID", evidence.backDocument),
            ("Document consistency", evidence.documentConsistency),
            ("ID portrait", evidence.portraitExtraction),
            ("Live capture quality", evidence.liveCaptureQuality),
            ("Face match", evidence.faceMatch.status),
            ("Liveness", evidence.liveness.status),
            ("Camera integrity", evidence.cameraIntegrity.status)
        ]

        for (name, status) in mandatory {
            switch status {
            case .passed:
                continue
            case .unavailable(let reason):
                reasons.append("\(name): \(reason)")
                return decision(.verificationUnavailable, reasons)
            case .inconclusive(let reason):
                reasons.append("\(name): \(reason)")
                return decision(.retryRequired, reasons)
            case .failed(let reason):
                reasons.append("\(name): \(reason)")
                return decision(.manualReviewRequired, reasons)
            }
        }

        return decision(.verified, [], authoritative: true)
    }

    private static func decision(
        _ outcome: PremiumVerificationOutcome,
        _ reasons: [String],
        authoritative: Bool = false
    ) -> PremiumVerificationDecision {
        PremiumVerificationDecision(
            outcome: outcome,
            reasons: reasons,
            policyVersion: policyVersion,
            clientIsAuthoritative: authoritative
        )
    }
}

protocol FaceEmbeddingProviding: Sendable {
    var modelIdentifier: String { get }
    func embedding(for image: UIImage) async throws -> [Float]
}

protocol LivenessDetecting: Sendable {
    var providerIdentifier: String { get }
    func evaluate(frames: [UIImage], activeChallengePassed: Bool) async -> LivenessResult
}

struct UnavailableFaceEmbeddingProvider: FaceEmbeddingProviding {
    let modelIdentifier = "unavailable"

    nonisolated init() {}

    func embedding(for image: UIImage) async throws -> [Float] {
        throw PremiumProviderError.faceModelUnavailable
    }
}

struct UnavailableLivenessProvider: LivenessDetecting {
    let providerIdentifier = "unavailable"

    nonisolated init() {}

    func evaluate(frames: [UIImage], activeChallengePassed: Bool) async -> LivenessResult {
        LivenessResult(
            status: .unavailable(reason: "A validated anti-spoofing model or SDK is required"),
            providerIdentifier: nil,
            activeChallengePassed: activeChallengePassed
        )
    }
}

enum PremiumProviderError: LocalizedError {
    case faceModelUnavailable
    case portraitNotFound
    case invalidEmbedding

    var errorDescription: String? {
        switch self {
        case .faceModelUnavailable: "A licensed face-embedding model is not installed."
        case .portraitNotFound: "No clear portrait was found on the ID."
        case .invalidEmbedding: "The biometric model returned an invalid embedding."
        }
    }
}
