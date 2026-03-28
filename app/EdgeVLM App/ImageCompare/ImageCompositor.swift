//
// ImageCompositor.swift
// EdgeVLM
//

import CoreGraphics
import CoreImage

/// Utility for compositing two images side-by-side into a single image.
enum ImageCompositor {

    /// Combine two images side-by-side into a single image.
    /// Both are resized to the same height, then placed left-right.
    /// - Parameters:
    ///   - left: The left image (Image A).
    ///   - right: The right image (Image B).
    ///   - targetHeight: The height both images are scaled to. Defaults to 512.
    /// - Returns: A combined `CIImage`, or `nil` if rendering fails.
    static func sideBySide(left: CIImage, right: CIImage, targetHeight: CGFloat = 512) -> CIImage? {
        let lScale = targetHeight / left.extent.height
        let rScale = targetHeight / right.extent.height
        let lw = left.extent.width * lScale
        let rw = right.extent.width * rScale
        let totalWidth = lw + rw

        let size = CGSize(width: totalWidth, height: targetHeight)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let ciContext = CIContext()

        if let leftCG = ciContext.createCGImage(left, from: left.extent) {
            context.draw(leftCG, in: CGRect(x: 0, y: 0, width: lw, height: targetHeight))
        }
        if let rightCG = ciContext.createCGImage(right, from: right.extent) {
            context.draw(rightCG, in: CGRect(x: lw, y: 0, width: rw, height: targetHeight))
        }

        guard let combined = context.makeImage() else { return nil }
        return CIImage(cgImage: combined)
    }
}
