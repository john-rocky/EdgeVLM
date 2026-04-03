//
// ConversationView.swift
// EdgeVLM App
//

import AVFoundation
import CoreImage
import MLXLMCommon
import PhotosUI
import SwiftUI
import Video

// Note: CVImageBuffer and CMSampleBuffer Sendable conformances
// are provided in ContentView.swift for the whole module.

/// Multi-turn conversation view.
/// Allows the user to capture an image from the camera and then
/// have a back-and-forth conversation about it with the VLM.
struct ConversationView: View {
    var model: EdgeVLMModel

    @State private var camera = CameraController()
    @State private var engine = ConversationEngine()

    /// Stream of frames for the live camera preview.
    @State private var framesToDisplay: AsyncStream<CVImageBuffer>?

    /// The text the user is currently typing.
    @State private var inputText: String = ""

    /// Whether the keyboard / input field is focused.
    @FocusState private var isInputFocused: Bool

    /// Photo library picker selection.
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
            VStack(spacing: 0) {
                if engine.capturedImage != nil {
                    // Image captured: show chat interface
                    capturedImageChat
                } else {
                    // No image yet: show live camera feed
                    cameraFeed
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
            .navigationTitle("Conversation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if engine.capturedImage != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            engine.reset()
                        } label: {
                            Label("New Image", systemImage: "camera.badge.ellipsis")
                        }
                    }
                }
            }
    }

    // MARK: - Camera Feed

    private var cameraFeed: some View {
        VStack {
            Spacer()

            if let framesToDisplay {
                VideoFrameView(
                    frames: framesToDisplay,
                    cameraType: .single,
                    action: { frame in
                        captureFrame(frame)
                    }
                )
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                #if os(macOS)
                .frame(maxWidth: 750)
                .frame(maxWidth: .infinity)
                .frame(minWidth: 500)
                .frame(minHeight: 375)
                #endif
            } else {
                ProgressView("Starting camera...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer()

            VStack(spacing: 12) {
                Text("Tap the shutter to capture, or select from your library.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images
                ) {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            if let newValue {
                loadPhoto(from: newValue)
            }
        }
    }

    // MARK: - Captured Image + Chat

    private var capturedImageChat: some View {
        VStack(spacing: 0) {
            // Scrollable area: captured image + messages
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        // Captured image thumbnail
                        capturedImagePreview
                            .padding(.top, 8)

                        // Message bubbles
                        ForEach(engine.messages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }

                        // Typing indicator while generating
                        if engine.isGenerating {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("typing-indicator")
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: engine.messages.count) { _, _ in
                    // Scroll to the latest message
                    if let lastMessage = engine.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: engine.isGenerating) { _, isGenerating in
                    if isGenerating {
                        withAnimation {
                            proxy.scrollTo("typing-indicator", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input bar
            inputBar
        }
    }

    private var capturedImagePreview: some View {
        Group {
            if let cgImage = renderCGImage(from: engine.capturedImage!) {
                #if os(iOS)
                Image(uiImage: UIImage(cgImage: cgImage))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                #elseif os(macOS)
                Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                #endif
            }
        }
    }

    private func messageBubble(_ message: ConversationMessage) -> some View {
        HStack {
            if message.role == .user { Spacer() }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.role == .user ? "You" : "EdgeVLM")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        message.role == .user
                            ? Color.blue.opacity(0.2)
                            : Color.gray.opacity(0.2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .textSelection(.enabled)
            }

            if message.role == .assistant { Spacer() }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about this image...", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .disabled(engine.isGenerating)
                .onSubmit {
                    sendMessage()
                }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || engine.isGenerating)
            #if os(macOS)
            .buttonStyle(.borderless)
            #endif
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func captureFrame(_ frame: CVImageBuffer) {
        let ciImage = CIImage(cvPixelBuffer: frame)
        engine.capturedImage = ciImage
    }

    private func loadPhoto(from item: PhotosPickerItem) {
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
            let ciImage = CIImage(cgImage: cgImage)
            await MainActor.run {
                engine.capturedImage = ciImage
                selectedPhotoItem = nil
            }
        }
    }

    private func sendMessage() {
        let question = inputText
        inputText = ""
        Task {
            await engine.ask(question: question, model: model)
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

    // MARK: - Helpers

    /// Render a CIImage to a CGImage for display.
    private func renderCGImage(from ciImage: CIImage) -> CGImage? {
        let context = CIContext()
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
}

#Preview {
    ConversationView(model: EdgeVLMModel())
}
