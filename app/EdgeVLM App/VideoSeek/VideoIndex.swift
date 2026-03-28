//
// VideoIndex.swift
// EdgeVLM
//
// Data model for video frame indexing and search.
//

import CoreGraphics
import Foundation

/// A single indexed entry representing a video frame with its caption.
struct IndexEntry: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    let caption: String
    let thumbnail: CGImage

    /// Formatted timestamp string (MM:SS).
    var formattedTimestamp: String {
        let minutes = Int(timestamp) / 60
        let seconds = Int(timestamp) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// A searchable collection of indexed video frame entries.
struct VideoIndex {
    private(set) var entries: [IndexEntry] = []

    /// Append a new entry to the index.
    mutating func addEntry(_ entry: IndexEntry) {
        entries.append(entry)
    }

    /// Clear all entries.
    mutating func clear() {
        entries.removeAll()
    }

    /// Search entries by keyword matching against captions.
    ///
    /// Splits the query into words and scores each caption by how many
    /// query words appear in it (case-insensitive). Returns entries
    /// sorted by score descending, filtered to score > 0.
    func search(query: String) -> [IndexEntry] {
        let queryWords = query
            .lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !queryWords.isEmpty else {
            return entries
        }

        let scored: [(entry: IndexEntry, score: Int)] = entries.compactMap { entry in
            let captionLower = entry.caption.lowercased()
            let score = queryWords.reduce(0) { total, word in
                total + (captionLower.contains(word) ? 1 : 0)
            }
            guard score > 0 else { return nil }
            return (entry, score)
        }

        return scored
            .sorted { $0.score > $1.score }
            .map(\.entry)
    }
}
