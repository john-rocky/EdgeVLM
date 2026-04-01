//
// NarrationView.swift
// EdgeVLM
//
// Continuous camera analysis with spoken descriptions for accessibility.
//

import AVFoundation
import CoreImage
import MLXLMCommon
import SwiftUI
import Video

// Sendable conformance for frame types (may already be declared in ContentView,
// but duplicate retroactive conformance is harmless in the same module).
extension CVImageBuffer: @unchecked @retroactive Sendable {}
extension CMSampleBuffer: @unchecked @retroactive Sendable {}

struct NarrationView: View {
    @State private var camera = CameraController()
    var model: EdgeVLMModel

    @State private var engine = NarrationEngine()

    /// Stream of frames forwarded to the camera preview.
    @State private var framesToDisplay: AsyncStream<CVImageBuffer>?

    private let narrationPrompt = "Describe the image in English."
    private let narrationSuffix = "Output should be brief, about 15 words or less."

    // MARK: - Body

    var body: some View {
            VStack(spacing: 0) {
                // Camera feed
                cameraSection

                // Controls & output
                controlsSection
            }
            #if os(iOS)
            .ignoresSafeArea(.keyboard)
            #endif
            .task {
                camera.start()
            }
            .task {
                await model.load()
            }
            .task {
                if Task.isCancelled { return }
                await distributeVideoFrames()
            }
            #if os(iOS)
            .onAppear {
                // Prevent the screen from dimming while narrating
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                engine.stop()
            }
            #else
            .onDisappear {
                engine.stop()
            }
            #endif
            .navigationTitle("Narration")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    // MARK: - Camera Section

    private var cameraSection: some View {
        Group {
            if let framesToDisplay {
                VideoFrameView(
                    frames: framesToDisplay,
                    cameraType: .continuous,
                    action: nil
                )
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                #if os(macOS)
                .frame(maxWidth: 750)
                #endif
                #if !os(macOS)
                .overlay(alignment: .topTrailing) {
                    CameraControlsView(
                        backCamera: $camera.backCamera,
                        device: $camera.device,
                        devices: $camera.devices
                    )
                    .padding()
                }
                #endif
                .overlay(alignment: .bottom) {
                    // Speaking indicator
                    if engine.isNarrating {
                        HStack(spacing: 6) {
                            if engine.isSpeaking {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.caption)
                                Text("Speaking")
                            } else {
                                Image(systemName: "eye.fill")
                                    .font(.caption)
                                Text("Analyzing")
                            }
                        }
                        .foregroundStyle(.white)
                        .font(.caption)
                        .bold()
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(engine.isSpeaking ? Color.blue : Color.green)
                        .clipShape(Capsule())
                        .padding(.bottom)
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
            }
        }
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        Form {
            // Start / Stop toggle
            Section {
                Button {
                    if engine.isNarrating {
                        engine.stop()
                    } else {
                        engine.isNarrating = true
                    }
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: engine.isNarrating
                              ? "stop.circle.fill"
                              : "play.circle.fill")
                            .font(.title2)
                        Text(engine.isNarrating ? "Stop Narration" : "Start Narration")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(engine.isNarrating ? .red : .accentColor)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            // Current description
            Section {
                if engine.currentDescription.isEmpty {
                    Text("No description yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(engine.currentDescription)
                        .textSelection(.enabled)
                        .frame(minHeight: 40)
                }
            } header: {
                Text("Current Description")
            }

            // Speech settings
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Speech Rate: \(String(format: "%.2f", engine.speechRate))")
                        .font(.subheadline)
                    Slider(value: $engine.speechRate, in: 0.3...0.6, step: 0.05)
                }

                Picker("Language", selection: $engine.voiceLanguage) {
                    ForEach(NarrationEngine.supportedLanguages, id: \.id) { lang in
                        Text(lang.label).tag(lang.id)
                    }
                }
            } header: {
                Text("Speech Settings")
            }

            // Volume indicator
            Section {
                HStack {
                    Image(systemName: volumeIcon)
                        .foregroundStyle(.secondary)
                    Text(engine.isSpeaking ? "Audio Active" : "Silent")
                        .foregroundStyle(engine.isSpeaking ? .primary : .secondary)
                }
            } header: {
                Text("Volume")
            }
        }
        #if os(iOS)
        .listSectionSpacing(0)
        #endif
    }

    // MARK: - Helpers

    private var volumeIcon: String {
        if engine.isSpeaking {
            return "speaker.wave.3.fill"
        } else if engine.isNarrating {
            return "speaker.fill"
        } else {
            return "speaker.slash.fill"
        }
    }

    // MARK: - Frame Distribution

    func distributeVideoFrames() async {
        let frames = AsyncStream<CMSampleBuffer>(bufferingPolicy: .bufferingNewest(1)) {
            camera.attach(continuation: $0)
        }

        let (framesToDisplay, displayCont) = AsyncStream.makeStream(
            of: CVImageBuffer.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.framesToDisplay = framesToDisplay

        let (framesToAnalyze, analyzeCont) = AsyncStream.makeStream(
            of: CVImageBuffer.self,
            bufferingPolicy: .bufferingNewest(1)
        )

        async let distribute: () = {
            for await sb in frames {
                if let frame = sb.imageBuffer {
                    displayCont.yield(frame)
                    if await self.engine.isNarrating {
                        analyzeCont.yield(frame)
                    }
                }
            }

            await MainActor.run {
                self.framesToDisplay = nil
                self.camera.detatch()
            }

            displayCont.finish()
            analyzeCont.finish()
        }()

        async let analyze: () = analyzeAndNarrate(framesToAnalyze)
        await distribute
        await analyze
    }

    /// Continuously capture frames, generate captions, and speak them.
    func analyzeAndNarrate(_ frames: AsyncStream<CVImageBuffer>) async {
        for await frame in frames {
            // Only process when narration is active
            guard await engine.isNarrating else { continue }

            let userInput = UserInput(
                prompt: .text("\(narrationPrompt) \(narrationSuffix)"),
                images: [.ciImage(CIImage(cvPixelBuffer: frame))]
            )

            do {
                let caption = try await model.generateCaption(userInput)
                guard await engine.isNarrating else { continue }
                await engine.speak(caption)
            } catch {
                // If generation fails (e.g. task cancelled), skip this frame
                continue
            }
        }
    }
}

#Preview {
    NarrationView(model: EdgeVLMModel())
}
