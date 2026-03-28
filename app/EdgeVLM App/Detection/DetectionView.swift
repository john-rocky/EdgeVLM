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
        NavigationStack {
            Form {
                // Camera + overlay section
                Section {
                    VStack(alignment: .leading, spacing: 10.0) {
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
                            .aspectRatio(4 / 3, contentMode: .fit)
                            #if os(macOS)
                            .frame(maxWidth: 750)
                            .frame(maxWidth: .infinity)
                            .frame(minWidth: 500)
                            .frame(minHeight: 375)
                            #endif
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                // Detected objects list
                if !detectedObjects.isEmpty {
                    Section {
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
                        }
                    } header: {
                        HStack {
                            Text("Detected Objects (\(detectedObjects.count))")
                            Spacer()
                            Button("Clear") {
                                clearDetections()
                            }
                            .font(.caption)
                        }
                        #if os(macOS)
                        .font(.headline)
                        .padding(.bottom, 2.0)
                        #endif
                    }
                }

                // Raw VLM output + debug info
                if !rawOutput.isEmpty {
                    Section {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(rawOutput)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                Text("Parsed: \(detectedObjects.count) objects")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                ForEach(detectedObjects) { obj in
                                    Text("\(obj.name): (\(String(format: "%.2f", obj.boundingBox.minX)), \(String(format: "%.2f", obj.boundingBox.minY)), \(String(format: "%.2f", obj.boundingBox.maxX)), \(String(format: "%.2f", obj.boundingBox.maxY)))")
                                        .font(.caption2)
                                        .monospaced()
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .frame(minHeight: 40, maxHeight: 200)
                    } header: {
                        Text("Raw Output")
                            #if os(macOS)
                            .font(.headline)
                            .padding(.bottom, 2.0)
                            #endif
                    }
                }

                #if os(macOS)
                Spacer()
                #endif
            }

            #if os(iOS)
            .listSectionSpacing(0)
            #elseif os(macOS)
            .padding()
            #endif
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

        Task {
            do {
                let output = try await model.generateCaption(userInput)
                await MainActor.run {
                    rawOutput = output
                    detectedObjects = DetectionParser.parse(output)
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

    /// Clear all detection results and resume camera feed.
    func clearDetections() {
        detectedObjects = []
        rawOutput = ""
    }
}

#Preview {
    DetectionView(model: EdgeVLMModel())
}
