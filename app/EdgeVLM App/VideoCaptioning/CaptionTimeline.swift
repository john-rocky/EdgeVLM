//
// CaptionTimeline.swift
// EdgeVLM
//

import Foundation

struct CaptionEntry: Identifiable {
    let id = UUID()
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String

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
}
