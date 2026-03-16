import CoreML
import Vision
import CoreImage
import UIKit
import ImageIO

struct IdentificationResult: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
}

enum PlantClassifierLoadError: Error {
    case modelNotFound
}

final class PlantClassifier {
    private let model: VNCoreMLModel
    private let visionQueue = DispatchQueue(label: "plant.classifier.vision.queue", qos: .userInitiated)
    private let probabilitySharpnessAlpha: Float = 3.0

    init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all

        // Load compiled CoreML model directly from bundle to avoid relying
        // on the auto‑generated `PlantIdentification` wrapper.
        guard let url = Bundle.main.url(forResource: "PlantIdentification", withExtension: "mlmodelc") else {
            throw PlantClassifierLoadError.modelNotFound
        }
        let coreMLModel = try MLModel(contentsOf: url, configuration: config)
        self.model = try VNCoreMLModel(for: coreMLModel)
    }

    func classify(pixelBuffer: CVPixelBuffer, completion: @escaping ([IdentificationResult]) -> Void) {
        visionQueue.async {
            let request = VNCoreMLRequest(model: self.model) { request, _ in
                if let results = request.results as? [VNClassificationObservation] {
                    let top = Array(results.prefix(5))
                    let mappedResults = Self.sharpenedNormalizedResults(
                        top,
                        alpha: self.probabilitySharpnessAlpha
                    )
                    DispatchQueue.main.async {
                        completion(mappedResults)
                    }
                }
            }

            request.imageCropAndScaleOption = .centerCrop

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([request])
            } catch {
                // Ignore per-frame errors to keep pipeline alive
            }
        }
    }

    func classify(uiImage: UIImage, completion: @escaping ([IdentificationResult]) -> Void) {
        guard let cgImage = uiImage.cgImage else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        let orientation = CGImagePropertyOrientation(uiImage.imageOrientation)
        visionQueue.async {
            let request = VNCoreMLRequest(model: self.model) { request, _ in
                if let results = request.results as? [VNClassificationObservation] {
                    let top = Array(results.prefix(5))
                    let mappedResults = Self.sharpenedNormalizedResults(
                        top,
                        alpha: self.probabilitySharpnessAlpha
                    )
                    DispatchQueue.main.async {
                        completion(mappedResults)
                    }
                } else {
                    DispatchQueue.main.async { completion([]) }
                }
            }
            request.imageCropAndScaleOption = .centerCrop

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async { completion([]) }
            }
        }
    }

    private static func sharpenedNormalizedResults(
        _ observations: [VNClassificationObservation],
        alpha: Float
    ) -> [IdentificationResult] {
        // Vision's `confidence` isn't guaranteed to be a calibrated probability.
        // For UI display, we map it into a probability-like distribution that:
        // - stays in [0, 1]
        // - sums to 1 (over the displayed top-k)
        // - preserves ranking
        // - increases separation when alpha > 1
        let weights: [Float] = observations.map { obs in
            let c = max(0, obs.confidence)
            return pow(c, alpha)
        }
        let total = weights.reduce(0, +)
        return zip(observations, weights).map { obs, w in
            let p = total > 0 ? (w / total) : 0
            return IdentificationResult(label: obs.identifier, confidence: p)
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
