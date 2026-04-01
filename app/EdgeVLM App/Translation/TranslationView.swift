//
// TranslationView.swift
// EdgeVLM
//

import AVFoundation
import CoreImage
import MLXLMCommon
import SwiftUI
import Video

// Support Swift 6 strict concurrency
extension CVImageBuffer: @unchecked @retroactive Sendable {}
extension CMSampleBuffer: @unchecked @retroactive Sendable {}

/// Live translation overlay view.
/// Captures a camera frame on tap, reads visible text using the VLM,
/// and displays the translation as an overlay on the camera feed.
struct TranslationView: View {
    var model: EdgeVLMModel

    @State private var camera = CameraController()
    @State private var framesToDisplay: AsyncStream<CVImageBuffer>?
    @State private var engine = TranslationEngine()
    @State private var selectedLanguage: LanguageOption = .english

    var body: some View {
            Form {
                // Camera feed with translation overlay
                Section {
                    VStack(alignment: .leading, spacing: 10.0) {
                        // Target language picker
                        Picker("Target Language", selection: $selectedLanguage) {
                            ForEach(LanguageOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .onChange(of: selectedLanguage) { _, newValue in
                            engine.targetLanguage = newValue.rawValue
                        }

                        if let framesToDisplay {
                            ZStack {
                                VideoFrameView(
                                    frames: framesToDisplay,
                                    cameraType: .single,
                                    action: { frame in
                                        captureAndTranslate(frame)
                                    }
                                )

                                // Translation overlay at the bottom of the camera view
                                if engine.isTranslating || !engine.translatedText.isEmpty {
                                    VStack {
                                        Spacer()
                                        translationOverlay
                                    }
                                    .allowsHitTesting(false)
                                }
                            }
                            .aspectRatio(4.0 / 3.0, contentMode: .fit)
                            #if os(macOS)
                                .frame(maxWidth: 750)
                                .frame(maxWidth: .infinity)
                                .frame(minWidth: 500)
                                .frame(minHeight: 375)
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
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                // Full translation result section
                if !engine.sourceText.isEmpty || !engine.translatedText.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            if !engine.sourceText.isEmpty {
                                Text("Original")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .bold()
                                Text(engine.sourceText)
                                    .textSelection(.enabled)
                                    #if os(macOS)
                                        .font(.headline)
                                        .fontWeight(.regular)
                                    #endif
                            }

                            if !engine.translatedText.isEmpty {
                                Divider()
                                Text("Translation (\(engine.targetLanguage))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .bold()
                                Text(engine.translatedText)
                                    .textSelection(.enabled)
                                    #if os(macOS)
                                        .font(.headline)
                                        .fontWeight(.regular)
                                    #endif
                            }
                        }
                        .frame(minHeight: 50)
                    } header: {
                        HStack {
                            Text("Result")
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

            .navigationTitle("Translate")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if !engine.translatedText.isEmpty {
                        Button {
                            clearResults()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
    }

    // MARK: - Translation Overlay

    /// Semi-transparent banner displayed at the bottom of the camera view.
    private var translationOverlay: some View {
        Group {
            if engine.isTranslating {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                    Text("Translating...")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.white)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.7))
            } else if !engine.translatedText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(engine.translatedText)
                        .font(.subheadline)
                        .bold()
                        .foregroundStyle(.white)
                        .lineLimit(3)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.7))
            }
        }
    }

    // MARK: - Frame Distribution

    /// Distribute camera frames to the display stream only (single capture mode).
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

    // MARK: - Actions

    /// Capture a single frame and run translation via the VLM.
    func captureAndTranslate(_ frame: CVImageBuffer) {
        guard !engine.isTranslating else { return }

        Task {
            await engine.translate(frame: frame, model: model)
        }
    }

    /// Clear all translation results.
    func clearResults() {
        engine.sourceText = ""
        engine.translatedText = ""
    }
}

#Preview {
    TranslationView(model: EdgeVLMModel())
}
