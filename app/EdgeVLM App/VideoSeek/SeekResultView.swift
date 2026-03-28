//
// SeekResultView.swift
// EdgeVLM
//
// Detail view showing a full-size frame image, caption, and timestamp.
//

import SwiftUI

struct SeekResultView: View {
    let entry: IndexEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Full-size frame image
                Image(decorative: entry.thumbnail, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // Timestamp
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text(entry.formattedTimestamp)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }

                // Caption
                VStack(alignment: .leading, spacing: 8) {
                    Text("Caption")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text(entry.caption)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
        .navigationTitle("Frame at \(entry.formattedTimestamp)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
