import AVFoundation
import SwiftUI

final class BarcodeScanner: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()
    var onCode: ((String) -> Void)?
    var onError: ((String) -> Void)?
    private let sessionQueue = DispatchQueue(label: "net.taxcurb.idchecker.capture")
    private var delivered = false
    private var cameraDevice: AVCaptureDevice?

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.inputs.isEmpty { self.configure() }
            self.delivered = false
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.setTorchLocked(false)
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func setTorch(_ isOn: Bool) {
        sessionQueue.async { [weak self] in self?.setTorchLocked(isOn) }
    }

    private func setTorchLocked(_ isOn: Bool) {
        guard let device = cameraDevice, device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if isOn, device.isTorchModeSupported(.on) {
                try device.setTorchModeOn(level: min(0.55, AVCaptureDevice.maxAvailableTorchLevel))
            } else if device.isTorchModeSupported(.off) {
                device.torchMode = .off
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.onError?("Flash is unavailable right now.")
            }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        defer { session.commitConfiguration() }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            onError?("Camera is unavailable")
            return
        }
        do {
            cameraDevice = camera
            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input) else { throw ScannerError.configuration }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { throw ScannerError.configuration }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: sessionQueue)
            if output.availableMetadataObjectTypes.contains(.pdf417) {
                output.metadataObjectTypes = [.pdf417]
            } else {
                throw ScannerError.pdf417Unavailable
            }
        } catch {
            onError?(error.localizedDescription)
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !delivered,
              let object = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
              object.type == .pdf417,
              let value = object.stringValue else { return }
        delivered = true
        DispatchQueue.main.async { [weak self] in self?.onCode?(value) }
    }

    private enum ScannerError: LocalizedError {
        case configuration
        case pdf417Unavailable

        var errorDescription: String? {
            switch self {
            case .configuration: "Unable to configure the camera"
            case .pdf417Unavailable: "PDF417 scanning is unavailable"
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
