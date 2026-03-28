//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import Foundation
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
    /// Handles variations: optional spaces around commas, integer or decimal coords.
    /// Coordinates are auto-detected as 0-100 or 0-1000 scale and normalized to 0-1.
    static func parse(_ output: String) -> [DetectedObject] {
        // Flexible: allow spaces around commas, decimal numbers
        guard let regex = try? NSRegularExpression(
            pattern: #"\[([^\]]+)\]\(\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*\)"#
        ) else { return [] }

        let nsOutput = output as NSString
        let range = NSRange(location: 0, length: nsOutput.length)
        let results = regex.matches(in: output, range: range)
        var objects: [DetectedObject] = []

        for match in results {
            guard match.numberOfRanges == 6 else { continue }
            let name = nsOutput.substring(with: match.range(at: 1))
            guard
                let x1 = Double(nsOutput.substring(with: match.range(at: 2))),
                let y1 = Double(nsOutput.substring(with: match.range(at: 3))),
                let x2 = Double(nsOutput.substring(with: match.range(at: 4))),
                let y2 = Double(nsOutput.substring(with: match.range(at: 5)))
            else { continue }

            // Determine coordinate scale (0-1, 0-100, or 0-1000)
            let maxCoord = max(x1, y1, x2, y2)
            let divisor: Double
            if maxCoord <= 1.0 {
                divisor = 1.0
            } else if maxCoord <= 100.0 {
                divisor = 100.0
            } else {
                divisor = 1000.0
            }

            let nx1 = x1 / divisor
            let ny1 = y1 / divisor
            let nx2 = x2 / divisor
            let ny2 = y2 / divisor

            guard nx1 >= 0, ny1 >= 0, nx2 >= 0, ny2 >= 0,
                  nx1 <= 1, ny1 <= 1, nx2 <= 1, ny2 <= 1,
                  nx2 > nx1, ny2 > ny1
            else { continue }

            let rect = CGRect(
                x: nx1,
                y: ny1,
                width: nx2 - nx1,
                height: ny2 - ny1
            )

            let color = palette[objects.count % palette.count]
            objects.append(DetectedObject(name: name, boundingBox: rect, color: color))
        }

        return objects
    }
}
