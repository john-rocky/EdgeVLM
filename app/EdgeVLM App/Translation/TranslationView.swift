//
// TranslationView.swift
// EdgeVLM
//

import AVFoundation
import CoreImage
import MLXLMCommon
import PhotosUI
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
    @State private var baseZoom: CGFloat = 1.0
    @State private var showZoomLevel = false
    @State private var selectedPhotoItem: PhotosPickerItem?

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

                                // Zoom level indicator
                                if showZoomLevel {
                                    VStack {
                                        Text(String(format: "%.1fx", camera.zoomFactor))
                                            .font(.caption)
                                            .bold()
                                            .foregroundStyle(.white)
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 8)
                                            .background(Color.black.opacity(0.6))
                                            .clipShape(Capsule())
                                            .padding(.top, 8)
                                        Spacer()
                                    }
                                }
                            }
                            .aspectRatio(9.0 / 16.0, contentMode: .fit)
                            #if os(iOS)
                            .gesture(
                                MagnifyGesture()
                                    .onChanged { value in
                                        camera.zoomFactor = baseZoom * value.magnification
                                        showZoomLevel = true
                                    }
                                    .onEnded { value in
                                        baseZoom = camera.zoomFactor
                                        Task {
                                            try? await Task.sleep(for: .seconds(1.5))
                                            showZoomLevel = false
                                        }
                                    }
                            )
                            #endif
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

                            if !engine.translatedText.isEmpty {
                                Divider()
                                HStack(spacing: 12) {
                                    Button {
                                        copyToClipboard(engine.translatedText)
                                    } label: {
                                        Label("Copy Translation", systemImage: "doc.on.doc")
                                    }
                                    .buttonStyle(.bordered)

                                    ShareLink(
                                        item: engine.translatedText,
                                        preview: SharePreview("Translation")
                                    ) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    .buttonStyle(.bordered)

                                    Spacer()
                                }
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
                    loadAndTranslatePhoto(newValue)
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

    /// Copy text to the system clipboard.
    func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
    }

    /// Clear all translation results.
    func clearResults() {
        engine.sourceText = ""
        engine.translatedText = ""
    }

    private var toolbarPhotoPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    /// Load a photo from the library and run translation on it.
    func loadAndTranslatePhoto(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            #if os(iOS)
            guard let uiImage = UIImage(data: data),
                  let cgImage = uiImage.cgImage else { return }
            #elseif os(macOS)
            guard let nsImage = NSImage(data: data),
                  let tiffData = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let cgImage = bitmap.cgImage else { return }
            #endif
            await MainActor.run {
                selectedPhotoItem = nil
            }
            await engine.translate(ciImage: CIImage(cgImage: cgImage), model: model)
        }
    }
}

#Preview {
    TranslationView(model: EdgeVLMModel())
}
