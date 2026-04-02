import Foundation
import CoreML
import CoreGraphics

// MARK: - Bounding Box (replaces SamBox)

/// Bounding box in pixel coordinates (xyxy format)
public struct DetectionBox {
    public let x0: Float
    public let y0: Float
    public let x1: Float
    public let y1: Float

    public init(x0: Float, y0: Float, x1: Float, y1: Float) {
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
    }
}

// MARK: - Model Reference

/// Reference to YOLO-World grounding model files
public struct GroundingModelRef {
    public let textEncoderURL: URL
    public let detectorURL: URL
    public let vocabularyURL: URL
    public let inputSize: Int
    public let maxClasses: Int
    public let contextLength: Int

    public init(
        textEncoderURL: URL,
        detectorURL: URL,
        vocabularyURL: URL,
        inputSize: Int = 640,
        maxClasses: Int = 80,
        contextLength: Int = 77
    ) {
        self.textEncoderURL = textEncoderURL
        self.detectorURL = detectorURL
        self.vocabularyURL = vocabularyURL
        self.inputSize = inputSize
        self.maxClasses = maxClasses
        self.contextLength = contextLength
    }

    /// Load grounding models from app bundle
    public static func bundled(
        textEncoderName: String = "clip_text_encoder",
        detectorName: String = "yoloworld_detector",
        vocabName: String = "clip_vocab"
    ) throws -> GroundingModelRef {
        // Search all bundles (main app + embedded frameworks)
        let bundles = [Bundle.main] + Bundle.allBundles

        func findResource(_ name: String, extensions: [String]) -> URL? {
            for bundle in bundles {
                for ext in extensions {
                    if let url = bundle.url(forResource: name, withExtension: ext) {
                        return url
                    }
                }
            }
            return nil
        }

        guard let textEncoderURL = findResource(textEncoderName, extensions: ["mlmodelc", "mlpackage"]) else {
            throw GroundingError.modelNotFound("Text encoder '\(textEncoderName)' not found in any bundle")
        }

        guard let detectorURL = findResource(detectorName, extensions: ["mlmodelc", "mlpackage"]) else {
            throw GroundingError.modelNotFound("Detector '\(detectorName)' not found in any bundle")
        }

        guard let vocabURL = findResource(vocabName, extensions: ["json"]) else {
            throw GroundingError.modelNotFound("Vocabulary '\(vocabName).json' not found in any bundle")
        }

        return GroundingModelRef(
            textEncoderURL: textEncoderURL,
            detectorURL: detectorURL,
            vocabularyURL: vocabURL
        )
    }
}

// MARK: - Detection Result

/// A single object detection from the grounding model
public struct GroundingResult {
    /// Bounding box in original image pixel coordinates
    public let box: DetectionBox
    /// Detection confidence score (0-1)
    public let confidence: Float
    /// Matched class label
    public let label: String

    public init(box: DetectionBox, confidence: Float, label: String) {
        self.box = box
        self.confidence = confidence
        self.label = label
    }
}

// MARK: - Options

/// Options for text-prompted detection
public struct TextPromptOptions {
    public let confidenceThreshold: Float
    public let nmsThreshold: Float
    public let maxDetections: Int

    public init(
        confidenceThreshold: Float = 0.01,
        nmsThreshold: Float = 0.5,
        maxDetections: Int = 10
    ) {
        self.confidenceThreshold = confidenceThreshold
        self.nmsThreshold = nmsThreshold
        self.maxDetections = maxDetections
    }
}

// MARK: - Errors

public enum GroundingError: LocalizedError {
    case modelNotFound(String)
    case invalidModelOutput(String)
    case tokenizationFailed(String)
    case detectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let msg): return "Model not found: \(msg)"
        case .invalidModelOutput(let msg): return "Invalid model output: \(msg)"
        case .tokenizationFailed(let msg): return "Tokenization failed: \(msg)"
        case .detectionFailed(let msg): return "Detection failed: \(msg)"
        }
    }
}
