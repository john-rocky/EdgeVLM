//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import AVFoundation
import CoreImage
import MLXLMCommon
import SwiftUI
import Video

/// View that captures a camera frame and uses the VLM to detect objects,
/// rendering bounding box overlays on the camera feed.
struct DetectionView: View {
    var model: EdgeVLMModel

    @State private var camera = CameraController()
    @State private var framesToDisplay: AsyncStream<CVImageBuffer>?
    @State private var lastCapturedFrame: CVImageBuffer?

    @State private var detectedObjects: [DetectedObject] = []
    @State private var rawOutput: String = ""
    @State private var isDetecting = false
    @State private var hold = false

    /// Detection prompt asking the VLM to output structured bounding boxes.
    private let detectionPrompt = """
        List all visible objects in this image. \
        For each object, output the format: [object_name](x1,y1,x2,y2) \
        where coordinates are percentages (0-100) of image width and height. \
        x1,y1 is top-left, x2,y2 is bottom-right.
        """

    var body: some View {
        VStack(spacing: 0) {
            // Camera + overlay
            if let framesToDisplay {
                ZStack {
                    VideoFrameView(
                        frames: framesToDisplay,
                        cameraType: .single,
                        action: { frame in
                            captureAndDetect(frame)
                        }
                    )

                    // Bounding box overlay
                    if !detectedObjects.isEmpty {
                        BoundingBoxOverlay(objects: detectedObjects)
                            .allowsHitTesting(false)
                    }

                    // Detection progress indicator
                    if isDetecting {
                        VStack {
                            Spacer()
                            HStack {
                                ProgressView()
                                    .tint(.white)
                                    .controlSize(.small)
                                Text("Detecting...")
                                    .font(.caption)
                                    .bold()
                                    .foregroundStyle(.white)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .padding(.bottom)
                        }
                    }
                }
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                #if os(macOS)
                .frame(maxWidth: 750)
                .frame(maxWidth: .infinity)
                .frame(minWidth: 500)
                .frame(minHeight: 375)
                #endif
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
            }

            Spacer(minLength: 0)

            // Results panel (fixed at bottom)
            resultsPanel
                .frame(maxHeight: 250)
        }
        .task {
            camera.start()
        }
        .task {
            await model.load()
        }

        #if !os(macOS)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        #endif

        .task {
            if Task.isCancelled { return }
            await distributeVideoFrames()
        }

        .navigationTitle("Detect")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !detectedObjects.isEmpty {
                    Button {
                        clearDetections()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Results Panel

    private var resultsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Detected objects list
                if !detectedObjects.isEmpty {
                    HStack {
                        Text("Detected Objects (\(detectedObjects.count))")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Button("Clear") {
                            clearDetections()
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal)

                    ForEach(detectedObjects) { object in
                        HStack {
                            Circle()
                                .fill(object.color)
                                .frame(width: 12, height: 12)
                            Text(object.name)
                                .font(.body)
                            Spacer()
                            Text(
                                String(
                                    format: "(%.0f,%.0f)-(%.0f,%.0f)",
                                    object.boundingBox.minX * 100,
                                    object.boundingBox.minY * 100,
                                    object.boundingBox.maxX * 100,
                                    object.boundingBox.maxY * 100
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospaced()
                        }
                        .padding(.horizontal)
                    }
                }

                // Raw VLM output
                if !rawOutput.isEmpty {
                    Text("Raw Output")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(rawOutput)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text("Parsed: \(detectedObjects.count) objects")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Frame Distribution

    func distributeVideoFrames() async {
        let frames = AsyncStream<CMSampleBuffer>(bufferingPolicy: .bufferingNewest(1)) {
            camera.attach(continuation: $0)
        }

        let (displayFrames, displayContinuation) = AsyncStream.makeStream(
            of: CVImageBuffer.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.framesToDisplay = displayFrames

        for await sampleBuffer in frames {
            if let frame = sampleBuffer.imageBuffer {
                displayContinuation.yield(frame)
            }
        }

        await MainActor.run {
            self.framesToDisplay = nil
            self.camera.detatch()
        }
        displayContinuation.finish()
    }

    // MARK: - Detection

    /// Capture a single frame and run object detection via the VLM.
    func captureAndDetect(_ frame: CVImageBuffer) {
        guard !isDetecting else { return }

        lastCapturedFrame = frame
        isDetecting = true
        detectedObjects = []
        rawOutput = ""

        let userInput = UserInput(
            prompt: .text(detectionPrompt),
            images: [.ciImage(CIImage(cvPixelBuffer: frame))]
        )

        // Compute aspect-fill crop adjustment
        let imageWidth = CGFloat(CVPixelBufferGetWidth(frame))
        let imageHeight = CGFloat(CVPixelBufferGetHeight(frame))
        let imageAspect = imageWidth / imageHeight
        let viewAspect: CGFloat = 4.0 / 3.0

        Task {
            do {
                let output = try await model.generateCaption(userInput)
                await MainActor.run {
                    rawOutput = output
                    detectedObjects = DetectionParser.parse(output).map { obj in
                        DetectedObject(
                            name: obj.name,
                            boundingBox: Self.adjustForAspectFill(
                                obj.boundingBox,
                                imageAspect: imageAspect,
                                viewAspect: viewAspect
                            ),
                            color: obj.color
                        )
                    }
                    isDetecting = false
                }
            } catch {
                await MainActor.run {
                    rawOutput = "Detection failed: \(error.localizedDescription)"
                    isDetecting = false
                }
            }
        }
    }

    /// Adjust normalized bounding box from image space to view space,
    /// accounting for resizeAspectFill cropping.
    static func adjustForAspectFill(
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

    /// Clear all detection results and resume camera feed.
    func clearDetections() {
        detectedObjects = []
        rawOutput = ""
    }
}

#Preview {
    DetectionView(model: EdgeVLMModel())
}
