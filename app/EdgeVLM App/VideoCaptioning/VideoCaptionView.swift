//
// VideoCaptionView.swift
// EdgeVLM
//

import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct VideoCaptionView: View {
    var model: EdgeVLMModel

    @State private var engine = VideoCaptionEngine()
    @State private var videoURL: URL?
    @State private var videoAsset: AVAsset?
    @State private var videoDuration: TimeInterval = 0

    @State private var interval: Double = 5.0
    @State private var prompt = "Describe what is happening in this frame. Be concise, about 15 words."

    @State private var showFileImporter = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showExporter = false
    @State private var videoThumbnail: CGImage?

    var body: some View {
        NavigationStack {
            Form {
                videoImportSection
                if videoAsset != nil {
                    configSection
                    controlSection
                }
                if engine.isProcessing || !engine.timeline.entries.isEmpty {
                    progressSection
                }
                if !engine.timeline.entries.isEmpty {
                    timelineSection
                    exportSection
                }
            }
            #if os(iOS)
            .listSectionSpacing(0)
            #elseif os(macOS)
            .padding()
            #endif
            .navigationTitle("Video Captioning")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .onChange(of: selectedPhotoItem) { _, newValue in
                if let newValue {
                    loadVideoFromPhotos(newValue)
                }
            }
            .task {
                await model.load()
            }
        }
    }

    // MARK: - Sections

    var videoImportSection: some View {
        Section {
            if let videoAsset {
                HStack {
                    if let videoThumbnail {
                        #if os(iOS)
                        Image(uiImage: UIImage(cgImage: videoThumbnail))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 60)
                            .clipped()
                            .cornerRadius(6)
                        #elseif os(macOS)
                        Image(nsImage: NSImage(cgImage: videoThumbnail, size: NSSize(width: 80, height: 60)))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 60)
                            .clipped()
                            .cornerRadius(6)
                        #endif
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(videoURL?.lastPathComponent ?? "Video")
                            .font(.headline)
                            .lineLimit(1)
                        Text(formatDuration(videoDuration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Change") {
                        showFileImporter = true
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)

                    Text("Select a video to generate captions")
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Browse Files", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)

                        PhotosPicker(
                            selection: $selectedPhotoItem,
                            matching: .videos
                        ) {
                            Label("Photo Library", systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        } header: {
            Text("Video")
                #if os(macOS)
                .font(.headline)
                .padding(.bottom, 2.0)
                #endif
        }
    }

    var configSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Interval")
                    Spacer()
                    Text("\(Int(interval))s")
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
                Slider(value: $interval, in: 1...30, step: 1)

                if videoDuration > 0 {
                    let frameCount = max(1, Int(ceil(videoDuration / interval)))
                    Text("\(frameCount) frames to process")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $prompt)
                    .frame(minHeight: 44)
                    #if os(macOS)
                    .padding(.horizontal, 8.0)
                    .padding(.vertical, 6.0)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(8.0)
                    #endif
            }
        } header: {
            Text("Settings")
                #if os(macOS)
                .font(.headline)
                .padding(.bottom, 2.0)
                #endif
        }
    }

    var controlSection: some View {
        Section {
            if engine.isProcessing {
                Button(role: .destructive) {
                    engine.cancel()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    startCaptioning()
                } label: {
                    Label("Generate Captions", systemImage: "captions.bubble")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.modelInfo != "Loaded")
            }

            if model.modelInfo != "Loaded" {
                Text(model.modelInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var progressSection: some View {
        Section {
            if engine.isProcessing {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: engine.progress)
                    HStack {
                        Text("Processing frame \(engine.processedFrames + 1) of \(engine.totalFrames)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(engine.progress * 100))%")
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let error = engine.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    var timelineSection: some View {
        Section {
            ForEach(engine.timeline.entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayTime)
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.blue)
                    Text(entry.text)
                        .font(.body)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
        } header: {
            HStack {
                Text("Captions (\(engine.timeline.entries.count))")
                    #if os(macOS)
                    .font(.headline)
                    #endif
                Spacer()
            }
        }
    }

    var exportSection: some View {
        Section {
            HStack(spacing: 12) {
                ShareLink(
                    item: engine.timeline.toSRT(),
                    preview: SharePreview("Captions.srt")
                ) {
                    Label("SRT", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)

                Button {
                    copyToClipboard(engine.timeline.toText())
                } label: {
                    Label("Copy Text", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
        } header: {
            Text("Export")
                #if os(macOS)
                .font(.headline)
                .padding(.bottom, 2.0)
                #endif
        }
    }

    // MARK: - Actions

    func startCaptioning() {
        guard let videoAsset else { return }
        engine.start(
            asset: videoAsset,
            interval: interval,
            prompt: prompt,
            model: model
        )
    }

    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            loadVideo(url: url)
        case .failure(let error):
            engine.error = error.localizedDescription
        }
    }

    func loadVideoFromPhotos(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            try? data.write(to: tempURL)
            await MainActor.run {
                loadVideo(url: tempURL)
            }
        }
    }

    func loadVideo(url: URL) {
        videoURL = url
        let asset = AVURLAsset(url: url)
        videoAsset = asset

        Task {
            if let duration = try? await asset.load(.duration) {
                videoDuration = CMTimeGetSeconds(duration)
            }
            // Generate thumbnail
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 240)
            if let (cgImage, _) = try? await generator.image(at: .zero) {
                videoThumbnail = cgImage
            }
        }
    }

    func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
