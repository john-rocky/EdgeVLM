//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import AVFoundation
import MLXLMCommon
import SwiftUI
import Video

// support swift 6
extension CVImageBuffer: @unchecked @retroactive Sendable {}
extension CMSampleBuffer: @unchecked @retroactive Sendable {}

// delay between frames -- controls the frame rate of the updates
let FRAME_DELAY = Duration.milliseconds(1)

struct ContentView: View {
    @State private var camera = CameraController()
    var model: EdgeVLMModel

    /// stream of frames -> VideoFrameView, see distributeVideoFrames
    @State private var framesToDisplay: AsyncStream<CVImageBuffer>?

    @State private var prompt = "Describe the image in English."
    @State private var promptSuffix = "Output should be brief, about 15 words or less."

    @State private var isShowingInfo: Bool = false

    @State private var selectedCameraType: CameraType = .continuous
    @State private var isEditingPrompt: Bool = false

    var toolbarItemPlacement: ToolbarItemPlacement {
        var placement: ToolbarItemPlacement = .navigation
        #if os(iOS)
        placement = .topBarLeading
        #endif
        return placement
    }

    var statusTextColor: Color {
        return model.evaluationState == .processingPrompt ? .black : .white
    }

    var statusBackgroundColor: Color {
        switch model.evaluationState {
        case .idle:
            return .gray
        case .generatingResponse:
            return .green
        case .processingPrompt:
            return .yellow
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Camera type picker
            Picker("Camera Type", selection: $selectedCameraType) {
                ForEach(CameraType.allCases, id: \.self) { cameraType in
                    Text(cameraType.rawValue.capitalized).tag(cameraType)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .onChange(of: selectedCameraType) { _, _ in
                model.cancel()
            }

            // Camera feed with caption overlay
            if let framesToDisplay {
                VideoFrameView(
                    frames: framesToDisplay,
                    cameraType: selectedCameraType,
                    action: { frame in
                        processSingleFrame(frame)
                    })
                    .aspectRatio(9.0/16.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .top) {
                        if !model.promptTime.isEmpty {
                            Text("TTFT \(model.promptTime)")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .monospaced()
                                .padding(.vertical, 4.0)
                                .padding(.horizontal, 6.0)
                                .background(alignment: .center) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.black.opacity(0.6))
                                }
                                .padding(.top)
                        }
                    }
                    #if !os(macOS)
                    .overlay(alignment: .topTrailing) {
                        CameraControlsView(
                            backCamera: $camera.backCamera,
                            device: $camera.device,
                            devices: $camera.devices)
                        .padding()
                    }
                    #endif
                    .overlay(alignment: .bottom) {
                        captionOverlay
                    }
                    .padding(.horizontal)
                    #if os(macOS)
                    .frame(maxWidth: 750)
                    .frame(maxWidth: .infinity)
                    .frame(minWidth: 500)
                    .frame(minHeight: 375)
                    #endif
            }

            Spacer(minLength: 0)

            // Prompt editing panel (only when editing)
            if isEditingPrompt {
                promptEditPanel
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
            if Task.isCancelled {
                return
            }

            await distributeVideoFrames()
        }

        .navigationTitle("Camera")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: toolbarItemPlacement) {
                Button {
                    isShowingInfo.toggle()
                }
                label: {
                    Image(systemName: "info.circle")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                if isEditingPrompt {
                    Button {
                        isEditingPrompt.toggle()
                    }
                    label: {
                        Text("Done")
                            .fontWeight(.bold)
                    }
                }
                else {
                    Menu {
                        Button("Describe image") {
                            prompt = "Describe the image in English."
                            promptSuffix = "Output should be brief, about 15 words or less."
                        }
                        Button("Facial expression") {
                            prompt = "What is this person's facial expression?"
                            promptSuffix = "Output only one or two words."
                        }
                        Button("Read text") {
                            prompt = "What is written in this image?"
                            promptSuffix = "Output only the text in the image."
                        }
                        #if !os(macOS)
                        Button("Customize...") {
                            isEditingPrompt.toggle()
                        }
                        #endif
                    } label: { Text("Prompts") }
                }
            }
        }
        .sheet(isPresented: $isShowingInfo) {
            InfoView()
        }
    }

    // MARK: - Caption Overlay

    private var captionOverlay: some View {
        VStack(spacing: 6) {
            // Status badge (continuous mode)
            if selectedCameraType == .continuous {
                HStack(spacing: 5) {
                    if model.evaluationState == .processingPrompt {
                        ProgressView()
                            .tint(statusTextColor)
                            .controlSize(.small)
                    } else if model.evaluationState == .idle {
                        Image(systemName: "clock.fill")
                            .font(.caption2)
                    } else {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption2)
                    }
                    Text(model.evaluationState.rawValue)
                        .font(.caption2)
                }
                .foregroundStyle(statusTextColor)
                .bold()
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(statusBackgroundColor)
                .clipShape(Capsule())
            }

            // Caption text
            if model.output.isEmpty && model.running {
                HStack(spacing: 6) {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                    Text("Analyzing...")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.white)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.7))
            } else if !model.output.isEmpty {
                Text(model.output)
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(.white)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.black.opacity(0.7))
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Prompt Edit Panel

    private var promptEditPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Prompt")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            #if os(iOS)
            TextField("Prompt", text: $prompt, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
            TextField("Suffix", text: $promptSuffix, axis: .vertical)
                .lineLimit(1...2)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            #elseif os(macOS)
            HStack(alignment: .top, spacing: 8) {
                TextEditor(text: $prompt)
                    .frame(height: 38)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(8)
                TextEditor(text: $promptSuffix)
                    .frame(height: 38)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(8)
            }
            #endif
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    func analyzeVideoFrames(_ frames: AsyncStream<CVImageBuffer>) async {
        for await frame in frames {
            let userInput = UserInput(
                prompt: .text("\(prompt) \(promptSuffix)"),
                images: [.ciImage(CIImage(cvPixelBuffer: frame))]
            )

            // generate output for a frame and wait for generation to complete
            let t = await model.generate(userInput)
            _ = await t.result

            do {
                try await Task.sleep(for: FRAME_DELAY)
            } catch { return }
        }
    }

    func distributeVideoFrames() async {
        // attach a stream to the camera -- this code will read this
        let frames = AsyncStream<CMSampleBuffer>(bufferingPolicy: .bufferingNewest(1)) {
            camera.attach(continuation: $0)
        }

        let (framesToDisplay, framesToDisplayContinuation) = AsyncStream.makeStream(
            of: CVImageBuffer.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.framesToDisplay = framesToDisplay

        // Only create analysis stream if in continuous mode
        let (framesToAnalyze, framesToAnalyzeContinuation) = AsyncStream.makeStream(
            of: CVImageBuffer.self,
            bufferingPolicy: .bufferingNewest(1)
        )

        // set up structured tasks (important -- this means the child tasks
        // are cancelled when the parent is cancelled)
        async let distributeFrames: () = {
            for await sampleBuffer in frames {
                if let frame = sampleBuffer.imageBuffer {
                    framesToDisplayContinuation.yield(frame)
                    // Only send frames for analysis in continuous mode
                    if await selectedCameraType == .continuous {
                        framesToAnalyzeContinuation.yield(frame)
                    }
                }
            }

            // detach from the camera controller and feed to the video view
            await MainActor.run {
                self.framesToDisplay = nil
                self.camera.detatch()
            }

            framesToDisplayContinuation.finish()
            framesToAnalyzeContinuation.finish()
        }()

        // Only analyze frames if in continuous mode
        if selectedCameraType == .continuous {
            async let analyze: () = analyzeVideoFrames(framesToAnalyze)
            await distributeFrames
            await analyze
        } else {
            await distributeFrames
        }
    }

    /// Perform EdgeVLM inference on a single frame.
    /// - Parameter frame: The frame to analyze.
    func processSingleFrame(_ frame: CVImageBuffer) {
        // Reset Response UI (show spinner)
        Task { @MainActor in
            model.output = ""
        }

        // Construct request to model
        let userInput = UserInput(
            prompt: .text("\(prompt) \(promptSuffix)"),
            images: [.ciImage(CIImage(cvPixelBuffer: frame))]
        )

        // Post request to EdgeVLM
        Task {
            await model.generate(userInput)
        }
    }
}

#Preview {
    ContentView(model: EdgeVLMModel())
}
