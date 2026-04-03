//
// CaptionDetailView.swift
// EdgeVLM
//

import SwiftUI

struct CaptionDetailView: View {
    let entry: CaptionEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let thumbnail = entry.thumbnail {
                    Image(decorative: thumbnail, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text(entry.displayTime)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }

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
    }
}
