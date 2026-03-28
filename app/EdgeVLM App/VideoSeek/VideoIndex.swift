//
// VideoIndex.swift
// EdgeVLM
//
// Data model for video frame indexing and search.
//

import CoreGraphics
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

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
    func search(query: String, expandedWords: [String] = []) -> [IndexEntry] {
        var allWords = query
            .lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        // Merge expanded synonyms from Foundation Models
        for word in expandedWords {
            let w = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !w.isEmpty && !allWords.contains(w) {
                allWords.append(w)
            }
        }

        guard !allWords.isEmpty else {
            return entries
        }

        let scored: [(entry: IndexEntry, score: Int)] = entries.compactMap { entry in
            let captionLower = entry.caption.lowercased()
            let score = allWords.reduce(0) { total, word in
                total + (captionLower.contains(word) ? 1 : 0)
            }
            guard score > 0 else { return nil }
            return (entry, score)
        }

        return scored
            .sorted { $0.score > $1.score }
            .map(\.entry)
    }

    /// Expand query using Foundation Models (iOS 26+ / macOS 26+).
    /// Returns synonyms and related words for broader matching.
    @MainActor
    func semanticSearch(query: String) async -> [IndexEntry] {
        let expanded = await Self.expandQuery(query)
        return search(query: query, expandedWords: expanded)
    }

    /// Use on-device LLM to generate synonyms and related words.
    @MainActor
    private static func expandQuery(_ query: String) async -> [String] {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            do {
                let session = LanguageModelSession()
                let prompt = """
                    List synonyms and closely related words for: "\(query)"
                    Output ONLY a comma-separated list of single words or short phrases. No explanations.
                    Example input: "dog running"
                    Example output: puppy, canine, pet, sprinting, jogging, dashing, moving
                    """
                let response = try await session.respond(to: prompt)
                let words = response.content
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                return words
            } catch {
                return []
            }
        }
        #endif
        return []
    }
}
