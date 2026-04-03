//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import AVFoundation
import CoreImage
import MLXLMCommon
import PhotosUI
import SwiftUI
import Video

/// View that captures a camera frame and runs YOLO-World detection + Vision segmentation,
/// displaying segmentation masks and bounding boxes on the camera feed.
struct SmartSegmentView: View {
    var model: EdgeVLMModel

    @State private var camera = CameraController()
    @State private var framesToDisplay: AsyncStream<CVImageBuffer>?
    @State private var engine = SmartSegmentEngine()
    @State private var isRunning = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        ZStack(alignment: .bottom) {
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
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                #if os(macOS)
                .frame(maxWidth: 750)
                .frame(maxWidth: .infinity)
                .frame(minWidth: 500)
                .frame(minHeight: 375)
                #endif
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Results panel (overlays at bottom)
            if engine.result != nil || engine.errorMessage != nil {
                resultsPanel
                    .frame(maxHeight: 250)
            }
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
            ToolbarItem(placement: toolbarPhotoPlacement) {
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images
                ) {
                    Image(systemName: "photo.on.rectangle")
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            if let newValue {
                loadAndSegmentPhoto(newValue)
            }
        }
    }

    // MARK: - Results Panel

    private var resultsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let error = engine.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                if let result = engine.result, !result.objects.isEmpty {
                    HStack {
                        Spacer()
                        Button("Clear") {
                            clearResults()
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal)

                    // Colored tags flow
                    FlowLayout(spacing: 8) {
                        ForEach(result.objects) { object in
                            Text(object.label)
                                .font(.subheadline)
                                .bold()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(object.color.opacity(0.85))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 10)
        }
        .background(.clear)
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
    // MARK: - Colored VLM Text

    private var toolbarPhotoPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    /// Load a photo from the library and run segmentation on it.
    func loadAndSegmentPhoto(_ item: PhotosPickerItem) {
        guard !isRunning else { return }
        isRunning = true
        engine.clear()

        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                await MainActor.run { isRunning = false }
                return
            }
            #if os(iOS)
            guard let uiImage = UIImage(data: data),
                  let cgImage = uiImage.cgImage else {
                await MainActor.run { isRunning = false }
                return
            }
            #elseif os(macOS)
            guard let nsImage = NSImage(data: data),
                  let tiffData = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let cgImage = bitmap.cgImage else {
                await MainActor.run { isRunning = false }
                return
            }
            #endif
            await MainActor.run {
                selectedPhotoItem = nil
            }
            await engine.run(ciImage: CIImage(cgImage: cgImage), model: model)
            await MainActor.run {
                isRunning = false
            }
        }
    }

    /// Build an AttributedString from VLM output, coloring detected object names.
    private func coloredVLMText(_ text: String, objects: [SegmentedObject]) -> Text {
        // Build a map of label → color
        var labelColors: [(String, Color)] = []
        for obj in objects {
            labelColors.append((obj.label.lowercased(), obj.color))
        }
        // Sort by length descending so longer labels match first
        labelColors.sort { $0.0.count > $1.0.count }

        // Walk through the text and build colored Text
        let lower = text.lowercased()
        var result = Text("")
        var i = lower.startIndex

        while i < lower.endIndex {
            var matched = false
            for (label, color) in labelColors {
                if lower[i...].hasPrefix(label) {
                    let end = text.index(i, offsetBy: label.count)
                    let word = String(text[i..<end])
                    result = result + Text(word).bold().foregroundColor(color)
                    i = end
                    matched = true
                    break
                }
            }
            if !matched {
                result = result + Text(String(text[i]))
                i = text.index(after: i)
            }
        }

        return result
    }
}

#Preview {
    SmartSegmentView(model: EdgeVLMModel())
}
