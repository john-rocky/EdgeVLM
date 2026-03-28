//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import SwiftUI

/// Draws colored bounding box rectangles with labels for detected objects.
struct BoundingBoxOverlay: View {
    let objects: [DetectedObject]

    var body: some View {
        GeometryReader { geometry in
            ForEach(objects) { object in
                let rect = CGRect(
                    x: object.boundingBox.minX * geometry.size.width,
                    y: object.boundingBox.minY * geometry.size.height,
                    width: object.boundingBox.width * geometry.size.width,
                    height: object.boundingBox.height * geometry.size.height
                )

                // Bounding box rectangle
                Rectangle()
                    .stroke(object.color, lineWidth: 2)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                // Label above the box
                Text(object.name)
                    .font(.caption2)
                    .bold()
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(object.color.opacity(0.7))
                    .foregroundStyle(.white)
                    .cornerRadius(4)
                    .position(
                        x: min(
                            max(rect.minX + 30, 30),
                            geometry.size.width - 30
                        ),
                        y: max(rect.minY - 10, 10)
                    )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: objects.map(\.id))
    }
}
