import Foundation
import Testing
@testable import IDChecker

struct VerificationDecisionEngineTests {
    @Test func localSessionCanNeverApprove() {
        var evidence = allPassedEvidence()
        evidence.faceMatch = FaceMatchResult(
            status: .passed,
            similarity: 0.9,
            modelIdentifier: "fixture",
            thresholdVersion: "test"
        )
        evidence.liveness = LivenessResult(
            status: .passed,
            providerIdentifier: "fixture",
            activeChallengePassed: true
        )

        let decision = VerificationDecisionEngine.evaluate(evidence, session: .local())

        #expect(decision.outcome == .verificationUnavailable)
        #expect(!decision.clientIsAuthoritative)
    }

    @Test func unavailableLivenessFailsClosed() {
        var evidence = allPassedEvidence()
        evidence.liveness = LivenessResult(
            status: .unavailable(reason: "No anti-spoofing provider"),
            providerIdentifier: nil,
            activeChallengePassed: true
        )
        let session = serverSession()

        let decision = VerificationDecisionEngine.evaluate(evidence, session: session)

        #expect(decision.outcome == .verificationUnavailable)
    }

    @Test func poorCaptureRequestsRetry() {
        var evidence = allPassedEvidence()
        evidence.liveCaptureQuality = .inconclusive(reason: "Blurred frames")

        let decision = VerificationDecisionEngine.evaluate(evidence, session: serverSession())

        #expect(decision.outcome == .retryRequired)
    }

    @Test func conflictingDocumentRequiresReview() {
        var evidence = allPassedEvidence()
        evidence.documentConsistency = .failed(reason: "DOB mismatch")

        let decision = VerificationDecisionEngine.evaluate(evidence, session: serverSession())

        #expect(decision.outcome == .manualReviewRequired)
    }

    private func allPassedEvidence() -> PremiumVerificationEvidence {
        PremiumVerificationEvidence(
            frontDocument: .passed,
            backDocument: .passed,
            documentConsistency: .passed,
            portraitExtraction: .passed,
            liveCaptureQuality: .passed,
            faceMatch: FaceMatchResult(
                status: .passed,
                similarity: 0.9,
                modelIdentifier: "fixture",
                thresholdVersion: "test"
            ),
            liveness: LivenessResult(
                status: .passed,
                providerIdentifier: "fixture",
                activeChallengePassed: true
            ),
            cameraIntegrity: CameraIntegrityResult(status: .passed, interruptionCount: 0)
        )
    }

    private func serverSession() -> VerificationSession {
        VerificationSession(
            id: UUID(),
            createdAt: .now,
            expiresAt: .now.addingTimeInterval(60),
            challengeNonce: Data([1, 2, 3]),
            serverIssued: true,
            attempt: 1
        )
    }
}
