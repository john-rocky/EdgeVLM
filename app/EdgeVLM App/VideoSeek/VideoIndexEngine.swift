//
// VideoIndexEngine.swift
// EdgeVLM
//
// Processing engine for extracting frames and generating captions.
//

import AVFoundation
import CoreImage
import Foundation
import MLXLMCommon

/// Engine that extracts frames from a video, generates captions using the VLM,
/// and builds a searchable VideoIndex.
@Observable
@MainActor
class VideoIndexEngine {

    /// Current processing progress (0.0 to 1.0).
    var progress: Double = 0.0

    /// Status message describing the current operation.
    var statusMessage: String = ""

    /// Whether the engine is currently indexing.
    var isIndexing: Bool = false

    /// The interval in seconds between extracted frames.
    var frameInterval: Double = 2.0

    /// The built index after processing completes.
    private(set) var videoIndex = VideoIndex()

    private var currentTask: Task<Void, Never>?

    /// Index a video at the given URL by extracting frames and generating captions.
    ///
    /// - Parameters:
    ///   - url: The file URL of the video.
    ///   - model: The EdgeVLM model used for caption generation.
    func indexVideo(url: URL, model: EdgeVLMModel) {
        cancel()

        videoIndex.clear()
        progress = 0.0
        isIndexing = true
        statusMessage = "Preparing video..."

        currentTask = Task {
            do {
                let asset = AVURLAsset(url: url)
                let duration = try await asset.load(.duration)
                let durationSeconds = CMTimeGetSeconds(duration)

                guard durationSeconds > 0 else {
                    statusMessage = "Invalid video duration"
                    isIndexing = false
                    return
                }

                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
                generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
                // Generate thumbnails at a reasonable size
                generator.maximumSize = CGSize(width: 640, height: 640)

                let frameCount = Int(durationSeconds / frameInterval) + 1
                var processedCount = 0

                for i in 0..<frameCount {
                    if Task.isCancelled { break }

                    let time = CMTime(seconds: Double(i) * frameInterval, preferredTimescale: 600)
                    let actualSeconds = CMTimeGetSeconds(time)

                    statusMessage = "Processing frame \(i + 1) of \(frameCount)..."

                    do {
                        let (cgImage, _) = try await generator.image(at: time)

                        // Generate caption using the VLM model
                        let ciImage = CIImage(cgImage: cgImage)
                        let userInput = UserInput(
                            prompt: .text("Describe this image in detail. Be specific about objects, people, actions, and the scene."),
                            images: [.ciImage(ciImage)]
                        )

                        let caption = try await model.generateCaption(userInput)

                        if Task.isCancelled { break }

                        let entry = IndexEntry(
                            timestamp: actualSeconds,
                            caption: caption,
                            thumbnail: cgImage
                        )
                        videoIndex.addEntry(entry)

                    } catch {
                        // Skip frames that fail to extract
                        print("Failed to process frame at \(actualSeconds)s: \(error)")
                    }

                    processedCount += 1
                    progress = Double(processedCount) / Double(frameCount)
                }

                if !Task.isCancelled {
                    statusMessage = "Indexing complete: \(videoIndex.entries.count) frames processed"
                }

            } catch {
                statusMessage = "Error: \(error.localizedDescription)"
            }

            isIndexing = false
        }
    }

    /// Cancel the current indexing operation.
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isIndexing = false
        statusMessage = ""
        progress = 0.0
    }
}
