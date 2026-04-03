//
// VideoCaptionEngine.swift
// EdgeVLM
//

import AVFoundation
import CoreImage
import MLXLMCommon

@Observable
@MainActor
class VideoCaptionEngine {
    var timeline = CaptionTimeline()
    var progress: Double = 0.0
    var isProcessing = false
    var currentFrameImage: CIImage?
    var error: String?
    var processedFrames = 0
    var totalFrames = 0

    private var processingTask: Task<Void, Never>?

    func start(
        asset: AVAsset,
        interval: TimeInterval,
        prompt: String,
        model: EdgeVLMModel
    ) {
        cancel()
        timeline = CaptionTimeline()
        progress = 0.0
        error = nil
        isProcessing = true
        processedFrames = 0

        processingTask = Task {
            do {
                let duration = try await asset.load(.duration)
                let totalSeconds = CMTimeGetSeconds(duration)
                totalFrames = max(1, Int(ceil(totalSeconds / interval)))

                let extractor = VideoFrameExtractor(asset: asset, interval: interval)
                let context = CIContext()

                for try await (time, ciImage) in extractor.extractFrames() {
                    if Task.isCancelled { break }

                    currentFrameImage = ciImage
                    let seconds = CMTimeGetSeconds(time)

                    // Generate thumbnail CGImage
                    let thumbSize = CGRect(origin: .zero, size: CGSize(width: 320, height: 240))
                    let scale = min(thumbSize.width / ciImage.extent.width,
                                    thumbSize.height / ciImage.extent.height)
                    let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    let thumbnail = context.createCGImage(scaled, from: scaled.extent)

                    let userInput = UserInput(
                        prompt: .text(prompt),
                        images: [.ciImage(ciImage)]
                    )

                    let caption = try await model.generateCaption(userInput)

                    let entry = CaptionEntry(
                        startTime: seconds,
                        endTime: min(seconds + interval, totalSeconds),
                        text: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                        thumbnail: thumbnail
                    )
                    timeline.entries.append(entry)
                    processedFrames += 1
                    progress = seconds / totalSeconds
                }

                if !Task.isCancelled {
                    progress = 1.0
                }
            } catch {
                if !Task.isCancelled {
                    self.error = error.localizedDescription
                }
            }

            isProcessing = false
        }
    }

    func cancel() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
    }
}
