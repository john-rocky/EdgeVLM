//
// CaptionDetailView.swift
// EdgeVLM
//

import AVKit
import SwiftUI

struct CaptionDetailView: View {
    let entry: CaptionEntry
    let videoURL: URL?

    @State private var player: AVPlayer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Video player or fallback thumbnail
                if let player {
                    VideoPlayer(player: player)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let thumbnail = entry.thumbnail {
                    Image(decorative: thumbnail, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Timestamp
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text(entry.displayTime)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }

                // Caption
                VStack(alignment: .leading, spacing: 8) {
                    Text("Caption")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text(entry.text)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
        .navigationTitle("Frame at \(entry.displayTime)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private func setupPlayer() {
        guard let videoURL else { return }
        let avPlayer = AVPlayer(url: videoURL)
        let seekTime = CMTime(seconds: entry.startTime, preferredTimescale: 600)
        avPlayer.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            avPlayer.play()
        }
        player = avPlayer
    }
}
