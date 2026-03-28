//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import SwiftUI

/// A single detected object with name, bounding box, and display color.
struct DetectedObject: Identifiable {
    let id = UUID()
    let name: String
    /// Normalized bounding box in 0-1 coordinate space.
    let boundingBox: CGRect
    let color: Color
}

/// Result of a detection pass, containing parsed objects and the raw VLM output.
struct DetectionResult {
    let objects: [DetectedObject]
    let rawOutput: String
}
