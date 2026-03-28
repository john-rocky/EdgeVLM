//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import SwiftUI

/// Parses VLM output text into structured detection results.
enum DetectionParser {

    /// Color palette for detected objects.
    static let palette: [Color] = [
        .red, .blue, .green, .orange, .purple,
        .pink, .yellow, .cyan, .mint, .teal
    ]

    /// Parse VLM output containing `[object_name](x1,y1,x2,y2)` entries.
    ///
    /// Coordinates in the VLM output are percentages (0-100) of image dimensions.
    /// They are normalized to 0-1 range in the returned `DetectedObject` values.
    /// Malformed entries are silently skipped.
    static func parse(_ output: String) -> [DetectedObject] {
        let pattern = /\[([^\]]+)\]\((\d+),(\d+),(\d+),(\d+)\)/
        var objects: [DetectedObject] = []

        for match in output.matches(of: pattern) {
            let name = String(match.1)
            guard
                let x1 = Double(match.2),
                let y1 = Double(match.3),
                let x2 = Double(match.4),
                let y2 = Double(match.5)
            else { continue }

            // Validate coordinate ranges
            guard x1 >= 0, y1 >= 0, x2 >= 0, y2 >= 0,
                  x1 <= 100, y1 <= 100, x2 <= 100, y2 <= 100,
                  x2 > x1, y2 > y1
            else { continue }

            let rect = CGRect(
                x: x1 / 100.0,
                y: y1 / 100.0,
                width: (x2 - x1) / 100.0,
                height: (y2 - y1) / 100.0
            )

            let color = palette[objects.count % palette.count]
            objects.append(DetectedObject(name: name, boundingBox: rect, color: color))
        }

        return objects
    }
}
