//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import AVFoundation
import CoreImage
import MLXLMCommon
import SwiftUI
import Video

/// View that captures a camera frame and runs VLM detection + Vision segmentation,
/// displaying segmentation masks and bounding boxes on the camera feed.
struct SmartSegmentView: View {
    var model: EdgeVLMModel

    @State private var camera = CameraController()
    @State private var framesToDisplay: AsyncStream<CVImageBuffer>?
    @State private var engine = SmartSegmentEngine()
    @State private var isRunning = false

    var body: some View {
        VStack(spacing: 0) {
            // Camera + overlay
            if let framesToDisplay {
                ZStack {
                    VideoFrameView(
                        frames: framesToDisplay,
                        cameraType: .single,
                        action: { frame in
                            captureAndSegment(frame)
                        }
                    )

                    // Segmentation overlay
                    if let result = engine.result, !result.objects.isEmpty {
                        SmartSegmentOverlay(objects: result.objects)
                            .allowsHitTesting(false)
                    }

                    // Pipeline progress indicator
                    if isRunning {
                        pipelineProgressOverlay
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

        .navigationTitle("Smart Segment")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if engine.result != nil {
                    Button {
                        clearResults()
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
                // Error message
                if let error = engine.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // Segmented objects list
                if let result = engine.result, !result.objects.isEmpty {
                    HStack {
                        Text("Segmented Objects (\(result.objects.count))")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Button("Clear") {
                            clearResults()
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal)

                    ForEach(result.objects) { object in
                        HStack {
                            Circle()
                                .fill(object.color)
                                .frame(width: 12, height: 12)
                            Text(object.label)
                                .font(.body)
                            Spacer()
                            if object.maskImage != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            } else {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // VLM Output
                if let result = engine.result {
                    Text("VLM Output")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal)

                    Text(result.vlmDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Pipeline Progress Overlay

    private var pipelineProgressOverlay: some View {
        VStack {
            Spacer()
            VStack(spacing: 4) {
                ProgressView()
                    .tint(.white)
                    .controlSize(.small)
                Text(engine.stage.rawValue)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.black.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.bottom)
        }
    }

    // MARK: - Actions

    func captureAndSegment(_ frame: CVImageBuffer) {
        guard !isRunning else { return }
        isRunning = true
        engine.clear()

        Task {
            await engine.run(frame: frame, model: model)
            isRunning = false
        }
    }

    func clearResults() {
        engine.clear()
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
}

#Preview {
    SmartSegmentView(model: EdgeVLMModel())
}
