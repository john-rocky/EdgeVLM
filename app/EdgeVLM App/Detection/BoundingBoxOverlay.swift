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
                ObjectBoxView(object: object, containerSize: geometry.size)
            }
        }
    }
}

/// Renders a single bounding box with label for one detected object.
private struct ObjectBoxView: View {
    let object: DetectedObject
    let containerSize: CGSize

    var scaledRect: CGRect {
        CGRect(
            x: object.boundingBox.minX * containerSize.width,
            y: object.boundingBox.minY * containerSize.height,
            width: object.boundingBox.width * containerSize.width,
            height: object.boundingBox.height * containerSize.height
        )
    }

    var body: some View {
        ZStack {
            Rectangle()
                .stroke(object.color, lineWidth: 2)
                .frame(width: scaledRect.width, height: scaledRect.height)
                .position(x: scaledRect.midX, y: scaledRect.midY)

            Text(object.name)
                .font(.caption2)
                .bold()
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(object.color.opacity(0.7))
                .foregroundStyle(.white)
                .cornerRadius(4)
                .position(
                    x: min(max(scaledRect.minX + 30, 30), containerSize.width - 30),
                    y: max(scaledRect.minY - 10, 10)
                )
        }
    }
}
