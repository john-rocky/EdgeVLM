//
// NarrationEngine.swift
// EdgeVLM
//
// Audio narration engine using AVSpeechSynthesizer.
//

import AVFoundation
import Foundation

/// Manages text-to-speech narration of image descriptions.
@Observable
@MainActor
class NarrationEngine: NSObject {

    // MARK: - Public state

    var isNarrating: Bool = false
    var currentDescription: String = ""
    var speechRate: Float = 0.5
    var voiceLanguage: String = "en-US"
    var isSpeaking: Bool = false

    // MARK: - Supported languages

    static let supportedLanguages: [(id: String, label: String)] = [
        ("en-US", "English"),
        ("ja-JP", "Japanese"),
    ]

    // MARK: - Private

    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenText: String = ""
    private var speechFinishedContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Init

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    /// Speak the given text aloud. Skips if the text matches the last spoken text.
    /// Returns after the utterance finishes playing.
    func speak(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Avoid repeating the exact same description
        if trimmed == lastSpokenText { return }
        lastSpokenText = trimmed

        currentDescription = trimmed

        // Stop any in-progress speech before starting a new one
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = speechRate
        if let voice = AVSpeechSynthesisVoice(language: voiceLanguage) {
            utterance.voice = voice
        }

        isSpeaking = true

        // Wait for the utterance to finish
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            speechFinishedContinuation = continuation
            synthesizer.speak(utterance)
        }

        isSpeaking = false
    }

    /// Stop any in-progress speech immediately.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        isNarrating = false
        lastSpokenText = ""

        // Resume any waiting continuation so the loop can exit cleanly
        if let continuation = speechFinishedContinuation {
            speechFinishedContinuation = nil
            continuation.resume()
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension NarrationEngine: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            if let continuation = speechFinishedContinuation {
                speechFinishedContinuation = nil
                continuation.resume()
            }
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            if let continuation = speechFinishedContinuation {
                speechFinishedContinuation = nil
                continuation.resume()
            }
        }
    }
}
