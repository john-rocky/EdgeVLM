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

                // Error message
                if let error = engine.errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                // Segmented objects list
                if let result = engine.result, !result.objects.isEmpty {
                    Section {
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
                        }
                    } header: {
                        HStack {
                            Text("Segmented Objects (\(result.objects.count))")
                            Spacer()
                            Button("Clear") {
                                clearResults()
                            }
                            .font(.caption)
                        }
                        #if os(macOS)
                        .font(.headline)
                        .padding(.bottom, 2.0)
                        #endif
                    }
                }

                // Debug info
                if let result = engine.result {
                    Section {
                        ScrollView {
                            Text(result.vlmDescription)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 30, maxHeight: 120)
                    } header: {
                        Text("VLM Output")
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
