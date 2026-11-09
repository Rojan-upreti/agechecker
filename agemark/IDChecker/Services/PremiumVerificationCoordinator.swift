import Foundation
import Observation
import UIKit

enum FaceCaptureStage: Equatable {
    case position
    case forward
    case turnLeft
    case turnRight
    case returnToCenter
    case analyzing
    case complete
    case failed(String)

    var instruction: LocalizedStringResource {
        switch self {
        case .position: "Position your face in the oval"
        case .forward: "Look straight at the camera"
        case .turnLeft: "Slowly turn your head left"
        case .turnRight: "Slowly turn your head right"
        case .returnToCenter: "Return to the center"
        case .analyzing: "Checking your capture"
        case .complete: "Capture complete"
        case .failed: "Capture needs attention"
        }
    }
}

@MainActor
@Observable
final class PremiumVerificationCoordinator {
    var stage: FaceCaptureStage = .position
    var feedback = "Position your face in the oval"
    var progress: Double = 0
    var currentStep = 1
    let totalSteps = 5
    var isReady = false
    var errorMessage: String?

    let camera = CameraSessionManager()
    private(set) var evidence: PremiumVerificationEvidence
    private(set) var session: VerificationSession
    private var stableFrames = 0
    private var bestFrames: [(Float, UIImage)] = []
    private var challengeStages: [FaceCaptureStage]
    private var challengeIndex = 0
    private var interruptionCount = 0
    private let portrait: UIImage
    private let embeddingProvider: any FaceEmbeddingProviding
    private let livenessProvider: any LivenessDetecting
    private let completion: (PremiumVerificationDecision) -> Void

    init(
        portrait: UIImage,
        initialEvidence: PremiumVerificationEvidence,
        session: VerificationSession,
        embeddingProvider: any FaceEmbeddingProviding = UnavailableFaceEmbeddingProvider(),
        livenessProvider: any LivenessDetecting = UnavailableLivenessProvider(),
        completion: @escaping (PremiumVerificationDecision) -> Void
    ) {
        self.portrait = portrait
        self.evidence = initialEvidence
        self.session = session
        self.embeddingProvider = embeddingProvider
        self.livenessProvider = livenessProvider
        self.completion = completion
        challengeStages = Bool.random() ? [.turnLeft, .turnRight] : [.turnRight, .turnLeft]

        camera.onAnalysis = { [weak self] analysis, image in
            self?.consume(analysis, image: image)
        }
        camera.onError = { [weak self] message in
            self?.errorMessage = message
            self?.stage = .failed(message)
        }
        camera.onInterruption = { [weak self] in
            guard let self else { return }
            interruptionCount += 1
            stableFrames = 0
            feedback = "Camera interrupted. Reposition your face."
        }
    }

    func start() {
        camera.start()
    }

    func cancel() {
        camera.stop()
    }

    func retry() {
        stableFrames = 0
        bestFrames.removeAll(keepingCapacity: true)
        challengeIndex = 0
        interruptionCount = 0
        challengeStages = Bool.random() ? [.turnLeft, .turnRight] : [.turnRight, .turnLeft]
        stage = .position
        currentStep = 1
        progress = 0
        errorMessage = nil
        camera.start()
    }

    private func consume(_ analysis: FaceAnalysis, image: UIImage?) {
        guard !isTerminal else { return }
        guard analysis.isSingleFace else {
            stableFrames = 0
            feedback = FaceQualityEvaluator.feedback(for: analysis)
            return
        }

        if let image, analysis.isHighQuality {
            bestFrames.append((analysis.captureQuality ?? 0, image))
            bestFrames.sort { $0.0 > $1.0 }
            if bestFrames.count > 8 { bestFrames.removeLast() }
        }

        switch stage {
        case .position:
            advanceWhen(analysis.isHighQuality, required: 3, progressRange: 0...0.16) {
                stage = .forward
                currentStep = 2
                feedback = "Look straight at the camera"
            }
        case .forward:
            let centeredPose = analysis.isHighQuality && abs(analysis.yaw ?? 1) < 0.12
            advanceWhen(centeredPose, required: 3, progressRange: 0.16...0.34) {
                stage = challengeStages[0]
                currentStep = 3
                feedback = String(localized: stage.instruction)
            }
        case .turnLeft:
            evaluateTurn(yaw: analysis.yaw, expectedPositive: true)
        case .turnRight:
            evaluateTurn(yaw: analysis.yaw, expectedPositive: false)
        case .returnToCenter:
            let centeredPose = analysis.isHighQuality && abs(analysis.yaw ?? 1) < 0.12
            advanceWhen(centeredPose, required: 3, progressRange: 0.78...0.94) {
                beginAnalysis()
            }
        case .analyzing, .complete, .failed:
            break
        }
    }

    private func evaluateTurn(yaw: Float?, expectedPositive: Bool) {
        guard let yaw else {
            stableFrames = 0
            feedback = "Turn slowly while keeping your face visible"
            return
        }
        let threshold: Float = 0.18
        let matches = expectedPositive ? yaw > threshold : yaw < -threshold
        let lower = challengeIndex == 0 ? 0.34 : 0.56
        let upper = challengeIndex == 0 ? 0.56 : 0.78
        advanceWhen(matches, required: 3, progressRange: lower...upper) {
            challengeIndex += 1
            if challengeIndex < challengeStages.count {
                stage = challengeStages[challengeIndex]
                currentStep = 4
                feedback = String(localized: stage.instruction)
            } else {
                stage = .returnToCenter
                currentStep = 5
                feedback = "Return to the center"
            }
        }
    }

    private func advanceWhen(
        _ condition: Bool,
        required: Int,
        progressRange: ClosedRange<Double>,
        completion: () -> Void
    ) {
        if condition {
            stableFrames += 1
            let fraction = min(1, Double(stableFrames) / Double(required))
            progress = progressRange.lowerBound + fraction * (progressRange.upperBound - progressRange.lowerBound)
            if stableFrames >= required {
                stableFrames = 0
                completion()
            }
        } else {
            stableFrames = 0
        }
    }

    private func beginAnalysis() {
        stage = .analyzing
        feedback = "Checking your capture"
        progress = 0.96
        camera.stop()
        let frames = bestFrames.map(\.1)
        let challengePassed = challengeIndex == challengeStages.count

        Task {
            evidence.liveCaptureQuality = frames.count >= 3
                ? .passed
                : .inconclusive(reason: "Not enough high-quality face frames")
            evidence.cameraIntegrity = interruptionCount == 0
                ? CameraIntegrityResult(status: .passed, interruptionCount: 0)
                : CameraIntegrityResult(
                    status: .inconclusive(reason: "The camera session was interrupted"),
                    interruptionCount: interruptionCount
                )
            evidence.liveness = await livenessProvider.evaluate(
                frames: frames,
                activeChallengePassed: challengePassed
            )
            evidence.faceMatch = await match(portrait: portrait, liveFrames: frames)
            let decision = VerificationDecisionEngine.evaluate(evidence, session: session)
            progress = 1
            stage = .complete
            completion(decision)
        }
    }

    private func match(portrait: UIImage, liveFrames: [UIImage]) async -> FaceMatchResult {
        guard !liveFrames.isEmpty else {
            return FaceMatchResult(
                status: .inconclusive(reason: "No suitable live face frames"),
                similarity: nil,
                modelIdentifier: nil,
                thresholdVersion: nil
            )
        }

        do {
            let reference = try await embeddingProvider.embedding(for: portrait)
            let live = try await liveFrames.asyncMap { try await embeddingProvider.embedding(for: $0) }
            guard !reference.isEmpty, live.allSatisfy({ $0.count == reference.count }) else {
                throw PremiumProviderError.invalidEmbedding
            }
            // A provider must supply its calibrated policy before this generic client can approve.
            return FaceMatchResult(
                status: .unavailable(reason: "No calibrated threshold policy is configured for this model"),
                similarity: nil,
                modelIdentifier: embeddingProvider.modelIdentifier,
                thresholdVersion: nil
            )
        } catch {
            return FaceMatchResult(
                status: .unavailable(reason: error.localizedDescription),
                similarity: nil,
                modelIdentifier: nil,
                thresholdVersion: nil
            )
        }
    }

    private var isTerminal: Bool {
        switch stage {
        case .analyzing, .complete, .failed: true
        default: false
        }
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var values: [T] = []
        values.reserveCapacity(count)
        for element in self {
            values.append(try await transform(element))
        }
        return values
    }
}
