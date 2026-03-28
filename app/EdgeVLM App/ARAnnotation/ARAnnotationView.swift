//
// ARAnnotationView.swift
// EdgeVLM
//
// Main view for the AR Annotation feature.
// Tap a point in the AR view to capture a frame, run VLM inference,
// and anchor a floating text label at that 3D position.
//

import SwiftUI
import MLXLMCommon
#if os(iOS)
import simd
#endif

struct ARAnnotationView: View {
    var model: EdgeVLMModel
    @State private var annotations: [ARAnnotation] = []
    @State private var isAnalyzing = false

    var body: some View {
        #if os(iOS)
        NavigationStack {
            ZStack {
                ARViewContainer(
                    annotations: $annotations,
                    onTap: { frame, position in
                        analyzeAndAnnotate(frame: frame, position: position)
                    }
                )
                .ignoresSafeArea()

                // UI overlays
                VStack {
                    Spacer()
                    if isAnalyzing {
                        ProgressView("Analyzing...")
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                    }

                    HStack {
                        Text("\(annotations.count) annotations")
                            .font(.caption)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                        Spacer()
                        if !annotations.isEmpty {
                            Button("Clear All") {
                                annotations.removeAll()
                            }
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("AR Annotate")
            .navigationBarTitleDisplayMode(.inline)
        }
        #else
        // macOS fallback — ARKit is not available
        VStack {
            Image(systemName: "arkit")
                .font(.largeTitle)
            Text("AR Annotation requires iOS")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

    #if os(iOS)
    /// Capture the current AR frame at the tapped position,
    /// run VLM inference, and place the resulting label in the scene.
    func analyzeAndAnnotate(frame: CVPixelBuffer, position: simd_float4x4) {
        guard !isAnalyzing else { return }
        isAnalyzing = true

        let ciImage = CIImage(cvPixelBuffer: frame)
        let userInput = UserInput(
            prompt: .text(
                "Describe the main object at the center of this image in 5 words or less."
            ),
            images: [.ciImage(ciImage)]
        )

        Task {
            do {
                let caption = try await model.generateCaption(userInput)
                let annotation = ARAnnotation(
                    text: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                    transform: position
                )
                annotations.append(annotation)
            } catch {
                // Silently ignore inference errors to keep the AR session running
            }
            isAnalyzing = false
        }
    }
    #endif
}
