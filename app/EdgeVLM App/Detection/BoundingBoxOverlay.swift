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
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                ForEach(objects) { object in
                    let x = object.boundingBox.minX * size.width
                    let y = object.boundingBox.minY * size.height
                    let w = object.boundingBox.width * size.width
                    let h = object.boundingBox.height * size.height

                    // Bounding box
                    Path { path in
                        path.addRect(CGRect(x: x, y: y, width: w, height: h))
                    }
                    .stroke(object.color, lineWidth: 2)

                    // Label
                    Text(object.name)
                        .font(.caption2)
                        .bold()
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(object.color.opacity(0.8))
                        .foregroundStyle(.white)
                        .cornerRadius(4)
                        .offset(x: x, y: max(y - 20, 0))
                }
            }
        }
    }
}
