//
// ImageCompareView.swift
// EdgeVLM
//

import CoreImage
import MLXLMCommon
import PhotosUI
import SwiftUI

/// View that lets users pick two images, composites them side-by-side,
/// and asks the VLM to describe the differences.
struct ImageCompareView: View {
    var model: EdgeVLMModel

    // MARK: - Image Selection State

    @State private var imageItemA: PhotosPickerItem?
    @State private var imageItemB: PhotosPickerItem?

    @State private var imageA: CIImage?
    @State private var imageB: CIImage?

    #if os(iOS)
    @State private var displayImageA: UIImage?
    @State private var displayImageB: UIImage?
    #elseif os(macOS)
    @State private var displayImageA: NSImage?
    @State private var displayImageB: NSImage?
    #endif

    // MARK: - Prompt State

    private let presetPrompts = [
        "Describe the differences between the two images.",
        "What changed between these images?",
        "Compare these two images in detail.",
    ]

    @State private var selectedPromptIndex = 0
    @State private var customPrompt = ""
    @State private var useCustomPrompt = false

    // MARK: - Result State

    @State private var resultText = ""
    @State private var isComparing = false
    @State private var errorMessage: String?

    // MARK: - Body

    var body: some View {
            Form {
                imageSelectionSection
                promptSection
                compareButtonSection
                resultSection
            }
            #if os(iOS)
            .listSectionSpacing(0)
            #elseif os(macOS)
            .padding()
            #endif
            .task {
                await model.load()
            }
            .navigationTitle("Compare")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if !resultText.isEmpty || imageA != nil || imageB != nil {
                        Button {
                            clearAll()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
    }

    // MARK: - Image Selection Section

    private var imageSelectionSection: some View {
        Section {
            HStack(spacing: 12) {
                imageSlot(
                    label: "Image A",
                    image: displayImageA,
                    pickerSelection: $imageItemA
                )
                imageSlot(
                    label: "Image B",
                    image: displayImageB,
                    pickerSelection: $imageItemB
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } header: {
            Text("Select Two Images")
                #if os(macOS)
                .font(.headline)
                .padding(.bottom, 2.0)
                #endif
        }
        .onChange(of: imageItemA) { _, newValue in
            Task { await loadImage(from: newValue, slot: .a) }
        }
        .onChange(of: imageItemB) { _, newValue in
            Task { await loadImage(from: newValue, slot: .b) }
        }
    }

    #if os(iOS)
    private func imageSlot(
        label: String,
        image: UIImage?,
        pickerSelection: Binding<PhotosPickerItem?>
    ) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            PhotosPicker(selection: pickerSelection, matching: .images) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    placeholderView
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    #elseif os(macOS)
    private func imageSlot(
        label: String,
        image: NSImage?,
        pickerSelection: Binding<PhotosPickerItem?>
    ) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            PhotosPicker(selection: pickerSelection, matching: .images) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    placeholderView
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    #endif

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.2))
            .frame(height: 150)
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.plus")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Tap to select")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        Section {
            Picker("Prompt", selection: $selectedPromptIndex) {
                ForEach(0..<presetPrompts.count, id: \.self) { index in
                    Text(presetPrompts[index]).tag(index)
                }
                Text("Custom...").tag(-1)
            }
            .onChange(of: selectedPromptIndex) { _, newValue in
                useCustomPrompt = (newValue == -1)
            }

            if useCustomPrompt {
                TextField("Enter your prompt", text: $customPrompt, axis: .vertical)
                    .lineLimit(2...4)
            }
        } header: {
            Text("Prompt")
                #if os(macOS)
                .font(.headline)
                .padding(.bottom, 2.0)
                #endif
        }
    }

    // MARK: - Compare Button Section

    private var compareButtonSection: some View {
        Section {
            Button {
                Task { await compare() }
            } label: {
                HStack {
                    Spacer()
                    if isComparing {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                        Text("Comparing...")
                    } else {
                        Image(systemName: "eyes")
                        Text("Compare")
                    }
                    Spacer()
                }
                .fontWeight(.semibold)
                .padding(.vertical, 4)
            }
            .disabled(!canCompare)
        }
    }

    // MARK: - Result Section

    @ViewBuilder
    private var resultSection: some View {
        if let errorMessage {
            Section {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            } header: {
                Text("Error")
                    #if os(macOS)
                    .font(.headline)
                    .padding(.bottom, 2.0)
                    #endif
            }
        }

        if !resultText.isEmpty {
            Section {
                ScrollView {
                    Text(resultText)
                        .textSelection(.enabled)
                        #if os(macOS)
                        .font(.headline)
                        .fontWeight(.regular)
                        #endif
                }
                .frame(minHeight: 50, maxHeight: 300)

                HStack(spacing: 12) {
                    Button {
                        copyToClipboard(resultText)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    ShareLink(
                        item: resultText,
                        preview: SharePreview("Comparison Result")
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            } header: {
                Text("Response")
                    #if os(macOS)
                    .font(.headline)
                    .padding(.bottom, 2.0)
                    #endif
            }
        }
    }

    // MARK: - Logic

    private var canCompare: Bool {
        imageA != nil && imageB != nil && !isComparing
    }

    private var activePrompt: String {
        if useCustomPrompt {
            return customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return presetPrompts[selectedPromptIndex]
    }

    private enum ImageSlot {
        case a, b
    }

    private func loadImage(from item: PhotosPickerItem?, slot: ImageSlot) async {
        guard let item else {
            await MainActor.run {
                switch slot {
                case .a:
                    imageA = nil
                    displayImageA = nil
                case .b:
                    imageB = nil
                    displayImageB = nil
                }
            }
            return
        }

        guard let data = try? await item.loadTransferable(type: Data.self) else { return }

        #if os(iOS)
        guard let uiImage = UIImage(data: data) else { return }
        guard let cgImage = uiImage.cgImage else { return }
        let ciImage = CIImage(cgImage: cgImage)
        await MainActor.run {
            switch slot {
            case .a:
                imageA = ciImage
                displayImageA = uiImage
            case .b:
                imageB = ciImage
                displayImageB = uiImage
            }
        }
        #elseif os(macOS)
        guard let nsImage = NSImage(data: data) else { return }
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let ciImage = CIImage(cgImage: cgImage)
        await MainActor.run {
            switch slot {
            case .a:
                imageA = ciImage
                displayImageA = nsImage
            case .b:
                imageB = ciImage
                displayImageB = nsImage
            }
        }
        #endif
    }

    private func compare() async {
        guard let imageA, let imageB else { return }

        await MainActor.run {
            isComparing = true
            resultText = ""
            errorMessage = nil
        }

        guard let composited = ImageCompositor.sideBySide(left: imageA, right: imageB) else {
            await MainActor.run {
                errorMessage = "Failed to composite images."
                isComparing = false
            }
            return
        }

        // Build the prompt with context about the side-by-side layout
        let contextPrefix =
            "The image shows two pictures side by side. " +
            "The left image is Image A and the right image is Image B. "
        let fullPrompt = contextPrefix + activePrompt

        let userInput = UserInput(
            prompt: .text(fullPrompt),
            images: [.ciImage(composited)]
        )

        do {
            let output = try await model.generateCaption(userInput)
            await MainActor.run {
                resultText = output
                isComparing = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Comparison failed: \(error.localizedDescription)"
                isComparing = false
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
    }

    private func clearAll() {
        imageItemA = nil
        imageItemB = nil
        imageA = nil
        imageB = nil
        displayImageA = nil
        displayImageB = nil
        resultText = ""
        errorMessage = nil
        customPrompt = ""
        selectedPromptIndex = 0
        useCustomPrompt = false
    }
}

#Preview {
    ImageCompareView(model: EdgeVLMModel())
}
