//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import CoreImage
import MLXLMCommon
import SwiftUI
import Vision

/// Orchestrates the VLM detection -> Vision segmentation pipeline.
@Observable
@MainActor
class SmartSegmentEngine {

    // MARK: - State

    enum PipelineStage: String {
        case idle = "Idle"
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

    /// Detection prompt asking the VLM to output structured bounding boxes.
    private let detectionPrompt = """
        List all visible objects in this image. \
        For each object, output the format: [object_name](x1,y1,x2,y2) \
        where coordinates are percentages (0-100) of image width and height. \
        x1,y1 is top-left, x2,y2 is bottom-right.
        """

    // MARK: - Pipeline

    func run(frame: CVImageBuffer, model: EdgeVLMModel) async {
        result = nil
        errorMessage = nil
        stage = .detectingObjects

        do {
            // Stage 1: VLM detects objects with bounding boxes
            let userInput = UserInput(
                prompt: .text(detectionPrompt),
                images: [.ciImage(CIImage(cvPixelBuffer: frame))]
            )
            let vlmOutput = try await model.generateCaption(userInput)
            let detectedObjects = DetectionParser.parse(vlmOutput)

            guard !detectedObjects.isEmpty else {
                errorMessage = "No objects detected"
                stage = .failed
                return
            }

            // Stage 2: Vision instance segmentation
            stage = .segmentingObjects

            let ciImage = CIImage(cvPixelBuffer: frame)
            let ciContext = CIContext()
            guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
                errorMessage = "Failed to convert frame"
                stage = .failed
                return
            }

            let instanceMasks = try await runInstanceSegmentation(on: cgImage)

            // Match VLM boxes to Vision instance masks
            let imageWidth = CGFloat(cgImage.width)
            let imageHeight = CGFloat(cgImage.height)
            let imageAspect = imageWidth / imageHeight
            let viewAspect: CGFloat = 4.0 / 3.0

            var objects: [SegmentedObject] = []
            for (i, detected) in detectedObjects.enumerated() {
                // Convert bounding box for aspect-fill display
                let rawBox = detected.boundingBox
                let viewBox = adjustForAspectFill(
                    rawBox, imageAspect: imageAspect, viewAspect: viewAspect
                )

                // Find best matching instance mask
                let maskImage = findBestMask(
                    for: rawBox,
                    from: instanceMasks,
                    imageWidth: Int(imageWidth),
                    imageHeight: Int(imageHeight),
                    color: Self.palette[i % Self.palette.count]
                )

                let color = Self.palette[i % Self.palette.count]
                objects.append(SegmentedObject(
                    label: detected.name,
                    boundingBox: viewBox,
                    maskImage: maskImage,
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

    // MARK: - Vision Instance Segmentation

    /// Run VNGenerateForegroundInstanceMaskRequest and return per-instance mask buffers.
    private func runInstanceSegmentation(
        on cgImage: CGImage
    ) async throws -> [(mask: CVPixelBuffer, bounds: CGRect)] {
        let handler = VNImageRequestHandler(cgImage: cgImage)
        let request = VNGenerateForegroundInstanceMaskRequest()

        try handler.perform([request])

        guard let observation = request.results?.first else {
            return []
        }

        var results: [(mask: CVPixelBuffer, bounds: CGRect)] = []
        for index in observation.allInstances {
            let maskBuffer = try observation.generateScaledMaskForImage(
                forInstances: IndexSet(integer: index),
                from: handler
            )
            // Compute normalized bounding box of this mask
            let bounds = computeMaskBounds(maskBuffer)
            results.append((mask: maskBuffer, bounds: bounds))
        }
        return results
    }

    /// Compute the normalized bounding box of non-zero pixels in a mask.
    private func computeMaskBounds(_ buffer: CVPixelBuffer) -> CGRect {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            return .zero
        }

        var minX = width, minY = height, maxX = 0, maxY = 0
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            for x in 0..<width {
                if ptr[y * bytesPerRow + x] > 128 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard maxX > minX, maxY > minY else { return .zero }

        return CGRect(
            x: CGFloat(minX) / CGFloat(width),
            y: CGFloat(minY) / CGFloat(height),
            width: CGFloat(maxX - minX) / CGFloat(width),
            height: CGFloat(maxY - minY) / CGFloat(height)
        )
    }

    /// Find the instance mask that best overlaps with a VLM bounding box, then colorize it.
    private func findBestMask(
        for box: CGRect,
        from instances: [(mask: CVPixelBuffer, bounds: CGRect)],
        imageWidth: Int,
        imageHeight: Int,
        color: Color
    ) -> CGImage? {
        guard !instances.isEmpty else { return nil }

        // Find instance with highest IoU against the VLM box
        var bestIdx = 0
        var bestIoU: CGFloat = 0
        for (i, instance) in instances.enumerated() {
            let iou = computeIoU(box, instance.bounds)
            if iou > bestIoU {
                bestIoU = iou
                bestIdx = i
            }
        }

        guard bestIoU > 0.05 else { return nil }

        return colorizeMask(
            instances[bestIdx].mask,
            color: color,
            width: imageWidth,
            height: imageHeight
        )
    }

    private func computeIoU(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let interArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - interArea
        return unionArea > 0 ? interArea / unionArea : 0
    }

    /// Convert a grayscale mask buffer to a colorized semi-transparent CGImage.
    private func colorizeMask(
        _ buffer: CVPixelBuffer,
        color: Color,
        width: Int,
        height: Int
    ) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let maskW = CVPixelBufferGetWidth(buffer)
        let maskH = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let maskPtr = base.assumingMemoryBound(to: UInt8.self)

        // Resolve color components
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

        // Create RGBA image at output size
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        guard let outPtr = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        let scaleX = Double(maskW) / Double(width)
        let scaleY = Double(maskH) / Double(height)

        for y in 0..<height {
            let my = min(Int(Double(y) * scaleY), maskH - 1)
            for x in 0..<width {
                let mx = min(Int(Double(x) * scaleX), maskW - 1)
                let maskVal = maskPtr[my * bytesPerRow + mx]
                let offset = (y * width + x) * 4
                if maskVal > 128 {
                    let alpha: UInt8 = 128
                    outPtr[offset + 0] = UInt8(UInt16(cr) * UInt16(alpha) / 255)
                    outPtr[offset + 1] = UInt8(UInt16(cg) * UInt16(alpha) / 255)
                    outPtr[offset + 2] = UInt8(UInt16(cb) * UInt16(alpha) / 255)
                    outPtr[offset + 3] = alpha
                } else {
                    outPtr[offset + 0] = 0
                    outPtr[offset + 1] = 0
                    outPtr[offset + 2] = 0
                    outPtr[offset + 3] = 0
                }
            }
        }

        return ctx.makeImage()
    }

    // MARK: - Coordinate Adjustment

    /// Adjust normalized bounding box from image space to view space,
    /// accounting for resizeAspectFill cropping.
    private func adjustForAspectFill(
        _ box: CGRect, imageAspect: CGFloat, viewAspect: CGFloat
    ) -> CGRect {
        if imageAspect < viewAspect {
            let visibleFraction = imageAspect / viewAspect
            let offset = (1 - visibleFraction) / 2
            return CGRect(
                x: box.minX,
                y: (box.minY - offset) / visibleFraction,
                width: box.width,
                height: box.height / visibleFraction
            )
        } else if imageAspect > viewAspect {
            let visibleFraction = viewAspect / imageAspect
            let offset = (1 - visibleFraction) / 2
            return CGRect(
                x: (box.minX - offset) / visibleFraction,
                y: box.minY,
                width: box.width / visibleFraction,
                height: box.height
            )
        }
        return box
    }

    // MARK: - Clear

    func clear() {
        result = nil
        errorMessage = nil
        stage = .idle
    }
}
