//
// CaptionTimeline.swift
// EdgeVLM
//

import CoreGraphics
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct CaptionEntry: Identifiable {
    let id = UUID()
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var thumbnail: CGImage?

    var startTimeFormatted: String { Self.formatSRT(startTime) }
    var endTimeFormatted: String { Self.formatSRT(endTime) }

    /// Format as HH:MM:SS,mmm for SRT
    static func formatSRT(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }

    /// Format as M:SS for display
    var displayTime: String {
        let minutes = Int(startTime) / 60
        let seconds = Int(startTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

@Observable
class CaptionTimeline {
    var entries: [CaptionEntry] = []

    func toSRT() -> String {
        entries.enumerated().map { index, entry in
            "\(index + 1)\n\(entry.startTimeFormatted) --> \(entry.endTimeFormatted)\n\(entry.text)"
        }.joined(separator: "\n\n")
    }

    func toText() -> String {
        entries.map { e in "[\(e.displayTime)] \(e.text)" }
            .joined(separator: "\n")
    }

    /// Search entries by keyword matching against captions.
    func search(query: String, expandedWords: [String] = []) -> [CaptionEntry] {
        var allWords = query
            .lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        for word in expandedWords {
            let w = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !w.isEmpty && !allWords.contains(w) {
                allWords.append(w)
            }
        }

        guard !allWords.isEmpty else { return entries }

        let scored: [(entry: CaptionEntry, score: Int)] = entries.compactMap { entry in
            let captionLower = entry.text.lowercased()
            let score = allWords.reduce(0) { total, word in
                total + (captionLower.contains(word) ? 1 : 0)
            }
            guard score > 0 else { return nil }
            return (entry, score)
        }

        return scored.sorted { $0.score > $1.score }.map(\.entry)
    }

    /// Expand query using Foundation Models and search.
    @MainActor
    func semanticSearch(query: String) async -> [CaptionEntry] {
        let expanded = await Self.expandQuery(query)
        return search(query: query, expandedWords: expanded)
    }

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
                return response.content
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            } catch {
                return []
            }
        }
        #endif
        return []
    }
}
