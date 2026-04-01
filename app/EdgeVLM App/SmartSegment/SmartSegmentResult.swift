//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import CoreGraphics
import SwiftUI

/// A single segmented object with VLM detection + Vision segmentation.
struct SegmentedObject: Identifiable {
    let id = UUID()
    let label: String
    /// Normalized bounding box in view coordinate space (accounts for aspect fill crop).
    let boundingBox: CGRect
    /// Colorized mask image (full image size, semi-transparent).
    let maskImage: CGImage?
    let color: Color
}

/// Complete result of the smart segment pipeline.
struct SmartSegmentResult {
    let objects: [SegmentedObject]
    /// Raw VLM output text.
    let vlmDescription: String
}
