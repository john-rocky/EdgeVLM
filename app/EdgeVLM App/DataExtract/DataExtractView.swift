//
// DataExtractView.swift
// EdgeVLM
//

import AVFoundation
import CoreImage
import MLXLMCommon
import PhotosUI
import SwiftUI
import Video

// Note: Sendable conformance for CVImageBuffer and CMSampleBuffer
// is declared in ContentView.swift

struct DataExtractView: View {
    var model: EdgeVLMModel

    // MARK: - Image Source

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: CGImage?
    @State private var showCamera = false
    @State private var camera = CameraController()
    @State private var capturedFrame: CVImageBuffer?

    // MARK: - Extraction Settings

    @State private var extractionMode: ExtractionMode = .receipt
    @State private var outputFormat: OutputFormat = .json
    @State private var customPrompt: String = ""

    // MARK: - Results

    @State private var extractedText: String = ""
    @State private var isExtracting = false
    @State private var errorMessage: String?
    @State private var copiedToClipboard = false

    var body: some View {
        NavigationStack {
            Form {
                imageSourceSection
                extractionSettingsSection
                if selectedImage != nil || capturedFrame != nil {
                    extractButtonSection
                }
                if isExtracting || !extractedText.isEmpty || errorMessage != nil {
                    resultSection
                }
            }
            #if os(iOS)
            .listSectionSpacing(0)
            #elseif os(macOS)
            .padding()
            #endif
            .navigationTitle("Data Extract")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onChange(of: selectedPhotoItem) { _, newValue in
                if let newValue {
                    loadImageFromPhotos(newValue)
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraCaptureSheet(
                    camera: camera,
                    onCapture: { frame in
                        capturedFrame = frame
                        selectedImage = nil
                        selectedPhotoItem = nil
                        showCamera = false
                    },
                    onCancel: {
                        showCamera = false
                    }
                )
            }
            .task {
                await model.load()
            }
        }
    }

    // MARK: - Image Source Section

    var imageSourceSection: some View {
        Section {
            if let selectedImage {
                VStack {
                    imagePreview(selectedImage)
                    changeImageButtons
                }
            } else if let capturedFrame {
                VStack {
                    cameraFramePreview(capturedFrame)
                    changeImageButtons
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)

                    Text("Select an image to extract data")
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        PhotosPicker(
                            selection: $selectedPhotoItem,
                            matching: .images
                        ) {
                            Label("Photo Library", systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            showCamera = true
                        } label: {
                            Label("Camera", systemImage: "camera")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        } header: {
            Text("Image")
                #if os(macOS)
                .font(.headline)
                .padding(.bottom, 2.0)
                #endif
        }
    }

    var changeImageButtons: some View {
        HStack(spacing: 12) {
            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .images
            ) {
                Label("Change", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered)

            Button {
                showCamera = true
            } label: {
                Label("Camera", systemImage: "camera")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(role: .destructive) {
                clearImage()
            } label: {
                Label("Remove", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 8)
    }

    // MARK: - Extraction Settings Section

    var extractionSettingsSection: some View {
        Section {
            Picker("Mode", selection: $extractionMode) {
                ForEach(ExtractionMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if extractionMode == .custom {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom Prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $customPrompt)
                        .frame(minHeight: 60)
                        #if os(macOS)
                        .padding(.horizontal, 8.0)
                        .padding(.vertical, 6.0)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(8.0)
                        #endif
                }
            } else {
                Text(extractionMode.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Output Format", selection: $outputFormat) {
                ForEach(OutputFormat.allCases, id: \.self) { format in
                    Text(format.rawValue).tag(format)
                }
            }
        } header: {
            Text("Extraction Settings")
                #if os(macOS)
                .font(.headline)
                .padding(.bottom, 2.0)
                #endif
        }
    }

    // MARK: - Extract Button Section

    var extractButtonSection: some View {
        Section {
            if isExtracting {
                Button(role: .destructive) {
                    isExtracting = false
                } label: {
                    Label("Cancel", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(true)
            } else {
                Button {
                    performExtraction()
                } label: {
                    Label("Extract Data", systemImage: "text.viewfinder")
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

    // MARK: - Result Section

    var resultSection: some View {
        Section {
            if isExtracting {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Extracting data...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if !extractedText.isEmpty {
                ScrollView {
                    Text(extractedText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 80, maxHeight: 400)

                HStack(spacing: 12) {
                    Button {
                        copyToClipboard(extractedText)
                    } label: {
                        Label(
                            copiedToClipboard ? "Copied!" : "Copy",
                            systemImage: copiedToClipboard ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .buttonStyle(.bordered)

                    ShareLink(
                        item: extractedText,
                        preview: SharePreview("Extracted Data")
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
        } header: {
            Text("Result")
                #if os(macOS)
                .font(.headline)
                .padding(.bottom, 2.0)
                #endif
        }
    }

    // MARK: - Image Preview Helpers

    func imagePreview(_ cgImage: CGImage) -> some View {
        #if os(iOS)
        Image(uiImage: UIImage(cgImage: cgImage))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxHeight: 250)
            .cornerRadius(8)
        #elseif os(macOS)
        Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxHeight: 250)
            .cornerRadius(8)
        #endif
    }

    func cameraFramePreview(_ frame: CVImageBuffer) -> some View {
        let ciImage = CIImage(cvPixelBuffer: frame)
        let context = CIContext()
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
        return Group {
            if let cgImage {
                imagePreview(cgImage)
            } else {
                Text("Preview unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    func loadImageFromPhotos(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            #if os(iOS)
            guard let uiImage = UIImage(data: data), let cgImage = uiImage.cgImage else { return }
            #elseif os(macOS)
            guard let nsImage = NSImage(data: data),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            #endif
            await MainActor.run {
                selectedImage = cgImage
                capturedFrame = nil
                extractedText = ""
                errorMessage = nil
            }
        }
    }

    func clearImage() {
        selectedImage = nil
        capturedFrame = nil
        selectedPhotoItem = nil
        extractedText = ""
        errorMessage = nil
    }

    func performExtraction() {
        guard !isExtracting else { return }

        let prompt: String
        if extractionMode == .custom {
            guard !customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "Please enter a custom prompt."
                return
            }
            prompt = customPrompt
        } else {
            prompt = extractionMode.prompt
        }

        // Append output format instruction
        let formatInstruction: String
        switch outputFormat {
        case .json:
            formatInstruction = " Output the result strictly as valid JSON."
        case .csv:
            formatInstruction = " Output the result strictly as CSV with headers."
        case .plainText:
            formatInstruction = " Output the result as plain text."
        }

        let fullPrompt = prompt + formatInstruction

        // Build the CIImage from whichever source we have
        let ciImage: CIImage
        if let capturedFrame {
            ciImage = CIImage(cvPixelBuffer: capturedFrame)
        } else if let selectedImage {
            ciImage = CIImage(cgImage: selectedImage)
        } else {
            errorMessage = "No image selected."
            return
        }

        isExtracting = true
        extractedText = ""
        errorMessage = nil
        copiedToClipboard = false

        let userInput = UserInput(
            prompt: .text(fullPrompt),
            images: [.ciImage(ciImage)]
        )

        Task {
            do {
                let output = try await model.generateCaption(userInput)
                await MainActor.run {
                    extractedText = output
                    isExtracting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Extraction failed: \(error.localizedDescription)"
                    isExtracting = false
                }
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
        copiedToClipboard = true

        // Reset the "Copied!" label after 2 seconds
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                copiedToClipboard = false
            }
        }
    }
}

// MARK: - Camera Capture Sheet

/// A sheet that presents a live camera preview and allows the user to capture a single frame.
struct CameraCaptureSheet: View {
    var camera: CameraController
    var onCapture: (CVImageBuffer) -> Void
    var onCancel: () -> Void

    @State private var framesToDisplay: AsyncStream<CVImageBuffer>?
    @State private var latestFrame: CVImageBuffer?

    var body: some View {
        NavigationStack {
            VStack {
                if let framesToDisplay {
                    VideoFrameView(
                        frames: framesToDisplay,
                        cameraType: .single,
                        action: { frame in
                            onCapture(frame)
                            camera.stop()
                        }
                    )
                    .aspectRatio(4 / 3, contentMode: .fit)
                } else {
                    ProgressView("Starting camera...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .task {
                camera.start()
            }
            .task {
                if Task.isCancelled { return }
                await distributeVideoFrames()
            }
            .navigationTitle("Capture Image")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        camera.stop()
                        onCancel()
                    }
                }
            }
        }
    }

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
    DataExtractView(model: EdgeVLMModel())
}
