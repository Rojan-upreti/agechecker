import AVFoundation
import CoreImage
import Foundation
import UIKit
@preconcurrency import Vision

enum FrontOCRService {
    nonisolated static func recognize(image: UIImage) async throws -> OCRData {
        guard let baseImage = CIImage(image: image) else { throw OCRError.invalidImage }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let enhanced = baseImage
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.45,
                kCIInputSaturationKey: 0.10,
                kCIInputBrightnessKey: 0.04
            ])
            .applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.85])

        let monochrome = baseImage
            .applyingFilter("CIPhotoEffectNoir")
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.65,
                kCIInputBrightnessKey: 0.04
            ])
            .applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 1.0])

        guard let originalCG = context.createCGImage(baseImage, from: baseImage.extent),
              let enhancedCG = context.createCGImage(enhanced, from: enhanced.extent),
              let monochromeCG = context.createCGImage(monochrome, from: monochrome.extent) else {
            throw OCRError.invalidImage
        }

        // Three accurate passes intentionally trade a little speed for better small-date recognition.
        async let originalCandidates = recognizeText(in: originalCG, languageCorrection: true)
        async let enhancedCandidates = recognizeText(in: enhancedCG, languageCorrection: true)
        async let monochromeCandidates = recognizeText(in: monochromeCG, languageCorrection: false)
        let candidates = try await originalCandidates + enhancedCandidates + monochromeCandidates
        return extract(from: candidates)
    }

    nonisolated private static func recognizeText(in image: CGImage, languageCorrection: Bool) async throws -> [VNRecognizedText] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let candidates = (request.results as? [VNRecognizedTextObservation])?
                    .flatMap { $0.topCandidates(3) } ?? []
                continuation.resume(returning: candidates)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = languageCorrection
            request.recognitionLanguages = ["en-US"]
            request.minimumTextHeight = 0.006
            request.customWords = [
                "DOB", "DATE OF BIRTH", "EXP", "EXPIRATION", "EXPIRES",
                "DL", "DLN", "DRIVER LICENSE", "LICENSE", "LIC NO",
                "LN", "FN", "LAST NAME", "FIRST NAME"
            ]

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private static func extract(from candidates: [VNRecognizedText]) -> OCRData {
        var seenLines = Set<String>()
        let uniqueLines = candidates
            .map { normalize($0.string) }
            .filter { !$0.isEmpty && seenLines.insert($0).inserted }
        let joined = uniqueLines.joined(separator: "\n")
        let averageConfidence = candidates.isEmpty
            ? 0
            : candidates.map(\.confidence).reduce(0, +) / Float(candidates.count)

        let allDateStrings = matches(
            #"\b(?:0?[1-9]|1[0-2])\s*[/\-. ]\s*(?:0?[1-9]|[12]\d|3[01])\s*[/\-. ]\s*(?:\d{2}|(?:19|20)\d{2})\b|\b(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])(?:\d{2}|(?:19|20)\d{2})\b"#,
            in: joined
        )
        let allDates = allDateStrings.compactMap(parseDate).sorted()

        let dob = taggedDate(
            labels: ["DOB", "DATE OF BIRTH", "BIRTH", "BORN"],
            lines: uniqueLines
        ) ?? allDates.filter { $0 <= Date() }.first

        let expiry = taggedDate(
            labels: ["EXP", "EXPIRATION", "EXPIRES", "EXP DATE"],
            lines: uniqueLines
        ) ?? allDates.filter { $0 > Date() }.last

        let license = firstCapturedValue(
            patterns: [
                #"(?i)\b(?:DLN|DL|LIC(?:ENSE)?|LIC NO|ID NO|ID NUMBER)\s*[:#.]?\s*([A-Z0-9][A-Z0-9 -]{3,19})"#,
                #"(?i)\b(?:CUSTOMER IDENTIFIER)\s*[:#.]?\s*([A-Z0-9][A-Z0-9 -]{3,19})"#
            ],
            in: joined
        ).map(cleanIdentifier)

        let lastName = labeledName(labels: ["LAST NAME", "LN"], lines: uniqueLines)
        let firstName = labeledName(labels: ["FIRST NAME", "FN", "GIVEN NAME"], lines: uniqueLines)
        let fullName = firstCapturedValue(
            patterns: [#"(?im)^\s*(?:NAME|FULL NAME)\s*[:.]?\s*([A-Z][A-Z ,'-]{3,40})\s*$"#],
            in: joined
        ).map(cleanName)

        let name: String?
        if let firstName, let lastName {
            name = "\(firstName) \(lastName)"
        } else {
            name = fullName
        }

        return OCRData(
            name: reliable(name),
            dateOfBirth: dob,
            expirationDate: expiry,
            licenseNumber: reliable(license),
            confidence: ["overall": averageConfidence]
        )
    }

    nonisolated private static func taggedDate(labels: [String], lines: [String]) -> Date? {
        let pattern = #"\b(?:0?[1-9]|1[0-2])\s*[/\-. ]\s*(?:0?[1-9]|[12]\d|3[01])\s*[/\-. ]\s*(?:\d{2}|(?:19|20)\d{2})\b|\b(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])(?:\d{2}|(?:19|20)\d{2})\b"#

        for index in lines.indices where labels.contains(where: { lines[index].localizedCaseInsensitiveContains($0) }) {
            let nearbyRange = max(lines.startIndex, index - 1)...min(lines.index(before: lines.endIndex), index + 2)
            let nearbyText = nearbyRange.map { lines[$0] }.joined(separator: " ")
            if let value = matches(pattern, in: nearbyText).first.flatMap(parseDate) {
                return value
            }
        }
        return nil
    }

    nonisolated private static func labeledName(labels: [String], lines: [String]) -> String? {
        for label in labels {
            let escaped = NSRegularExpression.escapedPattern(for: label)
            if let value = firstCapturedValue(
                patterns: ["(?im)^\\s*\(escaped)\\s*[:.]?\\s*([A-Z][A-Z ,'-]{1,35})\\s*$"],
                in: lines.joined(separator: "\n")
            ) {
                return cleanName(value)
            }
        }
        return nil
    }

    nonisolated private static func parseDate(_ value: String) -> Date? {
        let corrected = value
            .uppercased()
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "L", with: "1")
        let digits = corrected.filter(\.isNumber)
        guard digits.count == 6 || digits.count == 8,
              let month = Int(digits.prefix(2)),
              let day = Int(digits.dropFirst(2).prefix(2)) else { return nil }

        let year: Int
        if digits.count == 8, let parsedYear = Int(digits.suffix(4)) {
            year = parsedYear
        } else if let shortYear = Int(digits.suffix(2)) {
            let currentTwoDigitYear = Calendar.current.component(.year, from: .now) % 100
            year = shortYear > currentTwoDigitYear + 10 ? 1900 + shortYear : 2000 + shortYear
        } else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }

    nonisolated private static func normalize(_ value: String) -> String {
        value.uppercased()
            .replacingOccurrences(of: "|", with: "I")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func cleanIdentifier(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .punctuationCharacters)
    }

    nonisolated private static func cleanName(_ value: String) -> String {
        value.replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    nonisolated private static func reliable(_ value: String?) -> String? {
        guard let value, value.count >= 2 else { return nil }
        return value
    }

    nonisolated private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    nonisolated private static func firstCapturedValue(patterns: [String], in text: String) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let valueRange = Range(match.range(at: 1), in: text) else { continue }
            return String(text[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private enum OCRError: Error {
        case invalidImage
    }
}

final class FrontCaptureService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    var onCapture: ((UIImage) -> Void)?
    var onError: ((String) -> Void)?

    private let queue = DispatchQueue(label: "net.taxcurb.idchecker.front")
    private let imageContext = CIContext(options: [.useSoftwareRenderer: false])
    private var cameraDevice: AVCaptureDevice?
    private var lastAnalysis = Date.distantPast
    private var stableFrames = 0
    private var delivered = false
    private var latestImage: UIImage?

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.inputs.isEmpty { self.configure() }
            self.delivered = false
            self.stableFrames = 0
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.setTorchLocked(false)
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func captureNow() {
        queue.async { [weak self] in
            guard let self, !self.delivered, let image = self.latestImage else {
                DispatchQueue.main.async { [weak self] in self?.onError?("Hold the ID steady, then try again.") }
                return
            }
            self.deliver(image)
        }
    }

    func setTorch(_ isOn: Bool) {
        queue.async { [weak self] in self?.setTorchLocked(isOn) }
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
            DispatchQueue.main.async { [weak self] in self?.onError?("Flash is unavailable right now.") }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            DispatchQueue.main.async { [weak self] in self?.onError?("Camera is unavailable.") }
            return
        }
        cameraDevice = device
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        guard session.canAddOutput(output) else {
            DispatchQueue.main.async { [weak self] in self?.onError?("Unable to configure the camera.") }
            return
        }
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !delivered,
              Date().timeIntervalSince(lastAnalysis) > 0.3,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        lastAnalysis = Date()
        let orientedImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        guard let fullImage = makeUIImage(from: orientedImage) else { return }
        latestImage = fullImage

        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.52
        request.maximumAspectRatio = 0.75
        request.minimumSize = 0.32
        request.minimumConfidence = 0.65
        request.quadratureTolerance = 25
        request.maximumObservations = 1

        try? VNImageRequestHandler(ciImage: orientedImage, options: [:]).perform([request])
        guard let rectangle = request.results?.first else {
            stableFrames = 0
            return
        }

        stableFrames += 1
        guard stableFrames >= 3 else { return }
        deliver(correctedImage(orientedImage, rectangle: rectangle) ?? fullImage)
    }

    private func correctedImage(_ image: CIImage, rectangle: VNRectangleObservation) -> UIImage? {
        let extent = image.extent
        func point(_ normalized: CGPoint) -> CIVector {
            CIVector(x: extent.minX + normalized.x * extent.width, y: extent.minY + normalized.y * extent.height)
        }
        let corrected = image.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": point(rectangle.topLeft),
            "inputTopRight": point(rectangle.topRight),
            "inputBottomLeft": point(rectangle.bottomLeft),
            "inputBottomRight": point(rectangle.bottomRight)
        ])
        return makeUIImage(from: corrected)
    }

    private func makeUIImage(from image: CIImage) -> UIImage? {
        guard let cgImage = imageContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func deliver(_ image: UIImage) {
        guard !delivered else { return }
        delivered = true
        setTorchLocked(false)
        DispatchQueue.main.async { [weak self] in self?.onCapture?(image) }
    }
}
