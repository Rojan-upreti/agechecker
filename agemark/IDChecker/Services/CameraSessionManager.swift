import AVFoundation
import Foundation
import UIKit

final class CameraSessionManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    var onAnalysis: (@MainActor (FaceAnalysis, UIImage?) -> Void)?
    var onError: (@MainActor (String) -> Void)?
    var onInterruption: (@MainActor () -> Void)?

    private let sessionQueue = DispatchQueue(label: "net.taxcurb.idchecker.premium.camera")
    private let outputQueue = DispatchQueue(label: "net.taxcurb.idchecker.premium.frames", qos: .userInitiated)
    private let tracker = FaceTrackingService()
    private var frameIndex = 0
    private var analysisInFlight = false
    private var isConfigured = false
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        installObservers()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func start() {
        Task { [weak self] in
            guard let self else { return }
            let granted = await requestCameraAccess()
            guard granted else {
                await MainActor.run { self.onError?("Camera access is required for facial verification.") }
                return
            }
            sessionQueue.async { [weak self] in
                guard let self else { return }
                if !isConfigured { configure() }
                if isConfigured, !session.isRunning { session.startRunning() }
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if session.isRunning { session.stopRunning() }
        }
    }

    private func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .video)
        default:
            false
        }
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            Task { @MainActor in onError?("A front-facing camera is unavailable.") }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.setSampleBufferDelegate(self, queue: outputQueue)

            guard session.canAddInput(input), session.canAddOutput(output) else {
                throw CameraError.configuration
            }
            session.addInput(input)
            session.addOutput(output)
            if let connection = output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                connection.isVideoMirrored = connection.isVideoMirroringSupported
            }
            isConfigured = true
        } catch {
            Task { @MainActor in onError?(error.localizedDescription) }
        }
    }

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.onInterruption?() }
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            let message = (notification.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription
                ?? "The camera session was interrupted."
            Task { @MainActor in self.onError?(message) }
        })
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameIndex += 1
        guard frameIndex.isMultiple(of: 4), !analysisInFlight,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        analysisInFlight = true

        Task { [weak self] in
            guard let self else { return }
            defer { analysisInFlight = false }
            do {
                let analysis = try await tracker.analyze(pixelBuffer: pixelBuffer)
                let image = analysis.isHighQuality ? await tracker.image(from: pixelBuffer) : nil
                await MainActor.run { self.onAnalysis?(analysis, image) }
            } catch {
                await MainActor.run { self.onError?("Face analysis could not continue. Please try again.") }
            }
        }
    }

    private enum CameraError: LocalizedError {
        case configuration

        var errorDescription: String? { "Unable to configure the front camera." }
    }
}
