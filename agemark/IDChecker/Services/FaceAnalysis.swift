import CoreImage
import Foundation
import UIKit
@preconcurrency import Vision

struct FaceAnalysis: Equatable, Sendable {
    let faceCount: Int
    let boundingBox: CGRect?
    let yaw: Float?
    let roll: Float?
    let captureQuality: Float?
    let brightness: Float
    let sharpness: Float
    let hasLandmarks: Bool

    var isSingleFace: Bool { faceCount == 1 }

    var isCentered: Bool {
        guard let box = boundingBox else { return false }
        return abs(box.midX - 0.5) < 0.13 && abs(box.midY - 0.5) < 0.17
    }

    var isAppropriateSize: Bool {
        guard let box = boundingBox else { return false }
        return (0.18...0.58).contains(box.width) && (0.24...0.72).contains(box.height)
    }

    var isWellLit: Bool { brightness >= 0.12 && brightness <= 0.95 }
    var isSharp: Bool { sharpness >= 0.02 }
    var isHighQuality: Bool {
        isSingleFace && isCentered && isAppropriateSize && isWellLit && isSharp
            && (captureQuality ?? 0) >= 0.20 && hasLandmarks
    }
}

enum FaceQualityEvaluator {
    static func feedback(for analysis: FaceAnalysis) -> String {
        guard analysis.faceCount > 0 else { return "Position your face in the oval" }
        guard analysis.faceCount == 1 else { return "Only one person should be visible" }
        guard analysis.isCentered else { return "Center your face" }
        guard analysis.isAppropriateSize else { return "Move slightly closer" }
        guard analysis.isWellLit else { return "Move to even, brighter light" }
        guard analysis.isSharp else { return "Hold still" }
        guard (analysis.captureQuality ?? 0) >= 0.20 else { return "Face the camera and hold still" }
        return "Great — hold steady"
    }
}

actor FaceTrackingService {
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    func analyze(pixelBuffer: CVPixelBuffer) throws -> FaceAnalysis {
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(.leftMirrored)
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        landmarksRequest.revision = VNDetectFaceLandmarksRequestRevision3
        let qualityRequest = VNDetectFaceCaptureQualityRequest()
        qualityRequest.revision = VNDetectFaceCaptureQualityRequestRevision2
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up)
        try handler.perform([landmarksRequest, qualityRequest])

        let faces = landmarksRequest.results ?? []
        let qualityFaces = qualityRequest.results ?? []
        let face = faces.max { lhs, rhs in
            lhs.boundingBox.width * lhs.boundingBox.height < rhs.boundingBox.width * rhs.boundingBox.height
        }
        let qualityFace = face.flatMap { landmarkFace in
            qualityFaces.min {
                distance(from: $0.boundingBox, to: landmarkFace.boundingBox)
                    < distance(from: $1.boundingBox, to: landmarkFace.boundingBox)
            }
        }

        return FaceAnalysis(
            faceCount: faces.count,
            boundingBox: face?.boundingBox,
            yaw: face?.yaw?.floatValue,
            roll: face?.roll?.floatValue,
            captureQuality: qualityFace?.faceCaptureQuality,
            brightness: averageBrightness(of: image),
            sharpness: sharpness(of: image),
            hasLandmarks: face?.landmarks != nil
        )
    }

    func image(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(.leftMirrored)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func distance(from lhs: CGRect, to rhs: CGRect) -> CGFloat {
        hypot(lhs.midX - rhs.midX, lhs.midY - rhs.midY)
    }

    private func averageBrightness(of image: CIImage) -> Float {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return 0 }
        let vector = CIVector(x: extent.origin.x, y: extent.origin.y, z: extent.width, w: extent.height)
        let output = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: vector])
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return (0.2126 * Float(bitmap[0]) + 0.7152 * Float(bitmap[1]) + 0.0722 * Float(bitmap[2])) / 255
    }

    private func sharpness(of image: CIImage) -> Float {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return 0 }
        let edges = image
            .applyingFilter("CIPhotoEffectMono")
            .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 1])
        let vector = CIVector(x: extent.origin.x, y: extent.origin.y, z: extent.width, w: extent.height)
        let output = edges.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: vector])
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return Float(bitmap[0]) / 255
    }
}

enum IDPortraitExtractor {
    static func extract(from image: UIImage) async throws -> UIImage {
        guard let cgImage = image.cgImage else { throw PremiumProviderError.portraitNotFound }
        let orientation = image.cgImageOrientation
        return try await Task.detached(priority: .userInitiated) {
            let request = VNDetectFaceLandmarksRequest()
            try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
            guard let face = request.results?.max(by: {
                $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
            }) else {
                throw PremiumProviderError.portraitNotFound
            }

            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            let box = face.boundingBox
            var rect = CGRect(
                x: box.minX * width,
                y: (1 - box.maxY) * height,
                width: box.width * width,
                height: box.height * height
            )
            rect = rect.insetBy(dx: -rect.width * 0.35, dy: -rect.height * 0.28)
                .intersection(CGRect(x: 0, y: 0, width: width, height: height))
                .integral
            guard let cropped = cgImage.cropping(to: rect) else {
                throw PremiumProviderError.portraitNotFound
            }
            return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
        }.value
    }
}

private extension UIImage {
    var cgImageOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
