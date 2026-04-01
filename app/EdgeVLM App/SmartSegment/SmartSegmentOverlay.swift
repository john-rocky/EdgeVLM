//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import SwiftUI

/// Renders colorized segmentation masks and bounding boxes over the camera frame.
struct SmartSegmentOverlay: View {
    let objects: [SegmentedObject]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                // Layer 1: Colorized masks
                ForEach(objects) { object in
                    if let maskImage = object.maskImage {
                        #if os(iOS)
                        Image(uiImage: UIImage(cgImage: maskImage))
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .clipped()
                            .allowsHitTesting(false)
                        #elseif os(macOS)
                        Image(nsImage: NSImage(cgImage: maskImage, size: NSSize(width: maskImage.width, height: maskImage.height)))
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .clipped()
                            .allowsHitTesting(false)
                        #endif
                    }
                }

                // Layer 2: Bounding boxes and labels
                ForEach(objects) { object in
                    let x = object.boundingBox.minX * size.width
                    let y = object.boundingBox.minY * size.height
                    let w = object.boundingBox.width * size.width
                    let h = object.boundingBox.height * size.height

                    Path { path in
                        path.addRect(CGRect(x: x, y: y, width: w, height: h))
                    }
                    .stroke(object.color, lineWidth: 2)

                    Text(object.label)
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
