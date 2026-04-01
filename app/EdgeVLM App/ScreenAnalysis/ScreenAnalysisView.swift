//
// Screen Capture Analysis view for EdgeVLM.
// Allows users to paste or import a screenshot and ask questions about it.
//

import CoreImage
import MLXLMCommon
import PhotosUI
import SwiftUI

struct ScreenAnalysisView: View {
    var model: EdgeVLMModel

    @State private var capturedImage: CIImage?
    @State private var prompt: String = "Describe what you see in this screenshot."
    @State private var resultText: String = ""
    @State private var isAnalyzing: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    /// Preset prompts for common screenshot analysis tasks.
    private let presetPrompts: [(label: String, icon: String, prompt: String)] = [
        ("Explain this error", "exclamationmark.triangle", "Explain the error shown in this screenshot. What does it mean and how can it be fixed?"),
        ("Describe this UI", "rectangle.on.rectangle", "Describe the user interface shown in this screenshot in detail."),
        ("Read all text", "doc.text", "Read and transcribe all visible text in this screenshot."),
    ]

    var body: some View {
            Form {
                // Image import section
                Section {
                    VStack(spacing: 12) {
                        if let capturedImage {
                            let uiImage = renderCIImage(capturedImage)
                            if let uiImage {
                                Image(decorative: uiImage, scale: 1.0)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 300)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    #if os(macOS)
                                    .frame(maxWidth: 600)
                                    .frame(maxWidth: .infinity)
                                    #endif
                            }
                        } else {
                            // Placeholder when no image is loaded
                            VStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("Import a screenshot to analyze")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 150)
                        }

                        // Import buttons
                        HStack(spacing: 12) {
                            Button {
                                pasteFromClipboard()
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                            }
                            .buttonStyle(.bordered)

                            PhotosPicker(
                                selection: $selectedPhotoItem,
                                matching: .screenshots
                            ) {
                                Label("Photo Library", systemImage: "photo.on.rectangle")
                            }
                            .buttonStyle(.bordered)

                            if capturedImage != nil {
                                Button(role: .destructive) {
                                    clearAll()
                                } label: {
                                    Label("Clear", systemImage: "xmark.circle")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Screenshot")
                        #if os(macOS)
                        .font(.headline)
                        .padding(.bottom, 2.0)
                        #endif
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                // Prompt section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        #if os(iOS)
                        TextField("Ask about this screenshot...", text: $prompt, axis: .vertical)
                            .lineLimit(2...5)
                        #elseif os(macOS)
                        TextEditor(text: $prompt)
                            .frame(minHeight: 40, maxHeight: 80)
                            .padding(.horizontal, 8.0)
                            .padding(.vertical, 6.0)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(8.0)
                        #endif

                        // Preset prompt buttons
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(presetPrompts, id: \.label) { preset in
                                    Button {
                                        prompt = preset.prompt
                                    } label: {
                                        Label(preset.label, systemImage: preset.icon)
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Prompt")
                        #if os(macOS)
                        .font(.headline)
                        .padding(.bottom, 2.0)
                        #endif
                }

                // Analyze button section
                Section {
                    Button {
                        analyzeScreenshot()
                    } label: {
                        HStack {
                            Spacer()
                            if isAnalyzing {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 6)
                                Text("Analyzing...")
                            } else {
                                Label("Analyze Screenshot", systemImage: "sparkles")
                            }
                            Spacer()
                        }
                        .font(.headline)
                        .padding(.vertical, 4)
                    }
                    .disabled(capturedImage == nil || isAnalyzing || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                // Result section
                if !resultText.isEmpty || isAnalyzing {
                    Section {
                        if isAnalyzing && resultText.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.large)
                                    Text("Processing screenshot...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 12)
                        } else {
                            ScrollView {
                                Text(resultText)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    #if os(macOS)
                                    .font(.body)
                                    #endif
                            }
                            .frame(minHeight: 60, maxHeight: 300)
                        }
                    } header: {
                        HStack {
                            Text("Analysis Result")
                            Spacer()
                            if !resultText.isEmpty {
                                Button("Copy") {
                                    copyResultToClipboard()
                                }
                                .font(.caption)
                            }
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
                await model.load()
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                if let newItem {
                    loadPhoto(from: newItem)
                }
            }
            .navigationTitle("Screen Analysis")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if !resultText.isEmpty || capturedImage != nil {
                        Button {
                            clearAll()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
    }

    // MARK: - Clipboard Paste

    /// Paste an image from the system clipboard, converting to CIImage.
    private func pasteFromClipboard() {
        #if os(iOS)
        guard let uiImage = UIPasteboard.general.image else { return }
        guard let cgImage = uiImage.cgImage else { return }
        capturedImage = CIImage(cgImage: cgImage)
        resultText = ""
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        guard let objects = pasteboard.readObjects(forClasses: [NSImage.self], options: nil),
              let nsImage = objects.first as? NSImage else { return }
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else { return }
        capturedImage = CIImage(cgImage: cgImage)
        resultText = ""
        #endif
    }

    // MARK: - Photo Library

    /// Load a photo from the PhotosPicker selection.
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
            await MainActor.run {
                capturedImage = CIImage(cgImage: cgImage)
                resultText = ""
                selectedPhotoItem = nil
            }
        }
    }

    // MARK: - Analysis

    /// Send the captured screenshot and prompt to the model for analysis.
    private func analyzeScreenshot() {
        guard let capturedImage else { return }
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        isAnalyzing = true
        resultText = ""

        let userInput = UserInput(
            prompt: .text(trimmedPrompt),
            images: [.ciImage(capturedImage)]
        )

        Task {
            do {
                let output = try await model.generateCaption(userInput)
                await MainActor.run {
                    resultText = output
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    resultText = "Analysis failed: \(error.localizedDescription)"
                    isAnalyzing = false
                }
            }
        }
    }

    // MARK: - Helpers

    /// Render a CIImage to a CGImage for display.
    private func renderCIImage(_ ciImage: CIImage) -> CGImage? {
        let context = CIContext()
        return context.createCGImage(ciImage, from: ciImage.extent)
    }

    /// Copy the analysis result text to the system clipboard.
    private func copyResultToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = resultText
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(resultText, forType: .string)
        #endif
    }

    /// Clear all state and reset to initial view.
    private func clearAll() {
        capturedImage = nil
        resultText = ""
        selectedPhotoItem = nil
        prompt = "Describe what you see in this screenshot."
    }
}

#Preview {
    ScreenAnalysisView(model: EdgeVLMModel())
}
