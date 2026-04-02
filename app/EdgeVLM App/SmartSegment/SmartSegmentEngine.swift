//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import CoreImage
import CoreML
import MLXLMCommon
import SwiftUI
import Vision

/// Orchestrates VLM listing → YOLO-World detection → Vision segmentation pipeline.
@Observable
@MainActor
class SmartSegmentEngine {

    // MARK: - State

    enum PipelineStage: String {
        case idle = "Idle"
        case listingObjects = "Listing objects..."
        case detectingObjects = "Detecting objects..."
        case segmentingObjects = "Segmenting..."
        case complete = "Complete"
        case failed = "Failed"
    }

    var stage: PipelineStage = .idle
    var result: SmartSegmentResult?
    var errorMessage: String?

    // MARK: - Private

    static let palette: [Color] = [
        .red, .blue, .green, .orange, .purple,
        .pink, .yellow, .cyan, .mint, .teal
    ]

    /// VLM prompt for listing objects (no coordinates needed)
    private let listingPrompt = """
        List all visible objects in this image as a comma-separated list. \
        Output only object names, nothing else. Example: person, dog, car
        """

    /// YOLO-World detector (lazy loaded)
    private var detector: TextDetector?

    private func getDetector() throws -> TextDetector {
        if let detector { return detector }
        let modelRef = try GroundingModelRef.bundled()
        let det = try TextDetector(model: modelRef)
        self.detector = det
        return det
    }

    // MARK: - Pipeline

    func run(frame: CVImageBuffer, model: EdgeVLMModel) async {
        result = nil
        errorMessage = nil
        stage = .listingObjects

        do {
            // Stage 1: VLM lists objects (no coordinates)
            let ciImage = CIImage(cvPixelBuffer: frame)
            let userInput = UserInput(
                prompt: .text(listingPrompt),
                images: [.ciImage(ciImage)]
            )
            let vlmOutput = try await model.generateCaption(userInput)
            let queries = parseObjectList(vlmOutput)

            guard !queries.isEmpty else {
                errorMessage = "No objects listed"
                stage = .failed
                return
            }

            // Stage 2: YOLO-World detects objects with precise boxes
            stage = .detectingObjects

            let ciContext = CIContext()
            guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
                errorMessage = "Failed to convert frame"
                stage = .failed
                return
            }

            let detector = try getDetector()
            let detections = try detector.detect(
                image: cgImage,
                queries: queries,
                options: TextPromptOptions(confidenceThreshold: 0.05, maxDetections: 10)
            )

            guard !detections.isEmpty else {
                errorMessage = "No objects detected by YOLO-World"
                stage = .failed
                return
            }

            // Stage 3: Per-box Vision segmentation
            stage = .segmentingObjects

            let imageWidth = cgImage.width
            let imageHeight = cgImage.height

            var objects: [SegmentedObject] = []
            for (i, detection) in detections.enumerated() {
                let box = detection.box
                // Pixel box → clamp to image bounds
                let x0 = Int(max(0, box.x0))
                let y0 = Int(max(0, box.y0))
                let x1 = Int(min(Float(imageWidth), box.x1))
                let y1 = Int(min(Float(imageHeight), box.y1))
                let cropW = x1 - x0
                let cropH = y1 - y0
                guard cropW > 0, cropH > 0 else { continue }

                // Crop image to box region
                let cropRect = CGRect(x: x0, y: y0, width: cropW, height: cropH)
                guard let croppedCG = cgImage.cropping(to: cropRect) else { continue }

                // Run Vision foreground segmentation on the cropped region
                let cropMask = try? segmentForeground(on: croppedCG)

                // Build full-image mask by placing crop mask at the box position
                let color = Self.palette[i % Self.palette.count]
                let fullMask = cropMask.flatMap {
                    colorizeMaskAtPosition(
                        $0, color: color,
                        cropOrigin: (x0, y0),
                        imageWidth: imageWidth, imageHeight: imageHeight
                    )
                }

                // Normalized box for overlay
                let normalizedBox = CGRect(
                    x: CGFloat(box.x0) / CGFloat(imageWidth),
                    y: CGFloat(box.y0) / CGFloat(imageHeight),
                    width: CGFloat(box.x1 - box.x0) / CGFloat(imageWidth),
                    height: CGFloat(box.y1 - box.y0) / CGFloat(imageHeight)
                )

                objects.append(SegmentedObject(
                    label: detection.label,
                    boundingBox: normalizedBox,
                    maskImage: fullMask,
                    color: color
                ))
            }

            self.result = SmartSegmentResult(
                objects: objects,
                vlmDescription: vlmOutput
            )
            stage = .complete

        } catch {
            errorMessage = error.localizedDescription
            stage = .failed
        }
    }

    // MARK: - VLM Output Parsing

    /// Parse VLM output into a list of object names.
    private func parseObjectList(_ output: String) -> [String] {
        output
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0.count < 30 }
    }

    // MARK: - Per-Box Vision Segmentation

    /// Run foreground segmentation on a cropped image, return the mask buffer.
    private func segmentForeground(on cgImage: CGImage) throws -> CVPixelBuffer? {
        let handler = VNImageRequestHandler(cgImage: cgImage)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])

        guard let observation = request.results?.first,
              let firstInstance = observation.allInstances.first else {
            return nil
        }

        return try observation.generateScaledMaskForImage(
            forInstances: IndexSet(integer: firstInstance),
            from: handler
        )
    }

    /// Colorize a crop-sized Float32 mask and place it at the correct position in a full-image RGBA CGImage.
    private func colorizeMaskAtPosition(
        _ buffer: CVPixelBuffer,
        color: Color,
        cropOrigin: (x: Int, y: Int),
        imageWidth: Int,
        imageHeight: Int
    ) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let maskW = CVPixelBufferGetWidth(buffer)
        let maskH = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let maskPtr = base.assumingMemoryBound(to: Float32.self)
        let floatsPerRow = bytesPerRow / MemoryLayout<Float32>.stride

        #if os(iOS)
        let uiColor = UIColor(color)
        #elseif os(macOS)
        let uiColor = NSColor(color)
        #endif
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let cr = UInt8(r * 255)
        let cg = UInt8(g * 255)
        let cb = UInt8(b * 255)

        // Full-image canvas (transparent)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: imageWidth,
            height: imageHeight,
            bitsPerComponent: 8,
            bytesPerRow: imageWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        guard let outPtr = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        // Zero-fill (transparent)
        memset(outPtr, 0, imageWidth * imageHeight * 4)

        // Paint mask pixels at the crop's position in the full image
        for my in 0..<maskH {
            let imgY = cropOrigin.y + my
            guard imgY >= 0 && imgY < imageHeight else { continue }
            for mx in 0..<maskW {
                let imgX = cropOrigin.x + mx
                guard imgX >= 0 && imgX < imageWidth else { continue }
                let maskVal = maskPtr[my * floatsPerRow + mx]
                if maskVal > 0.5 {
                    let offset = (imgY * imageWidth + imgX) * 4
                    let alpha: UInt8 = 128
                    outPtr[offset + 0] = UInt8(UInt16(cr) * UInt16(alpha) / 255)
                    outPtr[offset + 1] = UInt8(UInt16(cg) * UInt16(alpha) / 255)
                    outPtr[offset + 2] = UInt8(UInt16(cb) * UInt16(alpha) / 255)
                    outPtr[offset + 3] = alpha
                }
            }
        }

        return ctx.makeImage()
    }

    // MARK: - Clear

    func clear() {
        result = nil
        errorMessage = nil
        stage = .idle
    }
}
