//
// VideoFrameExtractor.swift
// EdgeVLM
//

import AVFoundation
import CoreImage

struct VideoFrameExtractor {
    let asset: AVAsset
    let interval: TimeInterval

    func extractFrames() -> AsyncThrowingStream<(CMTime, CIImage), Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let duration = try await asset.load(.duration)
                    let durationSeconds = CMTimeGetSeconds(duration)

                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
                    generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
                    generator.maximumSize = CGSize(width: 1920, height: 1080)

                    var currentTime: TimeInterval = 0
                    while currentTime < durationSeconds {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        let cmTime = CMTime(seconds: currentTime, preferredTimescale: 600)
                        let (cgImage, actualTime) = try await generator.image(at: cmTime)
                        let ciImage = CIImage(cgImage: cgImage)
                        continuation.yield((actualTime, ciImage))
                        currentTime += interval
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    var estimatedFrameCount: Int {
        // Synchronous estimate; actual duration loaded lazily
        return max(1, Int(ceil(30.0 / interval)))  // fallback estimate
    }
}
