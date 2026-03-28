//
// TranslationEngine.swift
// EdgeVLM
//

import CoreImage
import Foundation
import MLXLMCommon

/// Manages text detection and translation state for live translation.
@Observable
@MainActor
class TranslationEngine {

    /// The original text detected in the captured frame.
    var sourceText: String = ""

    /// The translated text in the target language.
    var translatedText: String = ""

    /// Whether a translation request is currently in progress.
    var isTranslating: Bool = false

    /// The target language for translation.
    var targetLanguage: String = LanguageOption.english.rawValue

    /// Translate text visible in the given camera frame using a single VLM call.
    /// The model is asked to read all text and translate it to the target language,
    /// returning both the original and translated text in one response.
    func translate(frame: CVImageBuffer, model: EdgeVLMModel) async {
        guard !isTranslating else { return }

        isTranslating = true
        sourceText = ""
        translatedText = ""

        let prompt = """
            Read all text in this image and translate it to \(targetLanguage). \
            First show the original text under "Original:", then show the translation under "Translation:".
            """

        let userInput = UserInput(
            prompt: .text(prompt),
            images: [.ciImage(CIImage(cvPixelBuffer: frame))]
        )

        do {
            let output = try await model.generateCaption(userInput)
            parseOutput(output)
        } catch {
            translatedText = "Translation failed: \(error.localizedDescription)"
        }

        isTranslating = false
    }

    /// Parse the VLM output to extract original and translated text.
    /// Expected format:
    ///   Original: <text>
    ///   Translation: <text>
    private func parseOutput(_ output: String) {
        let lines = output.components(separatedBy: "\n")

        var foundOriginal = false
        var foundTranslation = false
        var originalLines: [String] = []
        var translationLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.lowercased().hasPrefix("original:") {
                foundOriginal = true
                foundTranslation = false
                let rest = trimmed.dropFirst("original:".count)
                    .trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty {
                    originalLines.append(rest)
                }
            } else if trimmed.lowercased().hasPrefix("translation:") {
                foundTranslation = true
                foundOriginal = false
                let rest = trimmed.dropFirst("translation:".count)
                    .trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty {
                    translationLines.append(rest)
                }
            } else if foundTranslation {
                translationLines.append(trimmed)
            } else if foundOriginal {
                originalLines.append(trimmed)
            }
        }

        sourceText =
            originalLines.isEmpty
            ? output.trimmingCharacters(in: .whitespacesAndNewlines)
            : originalLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        translatedText =
            translationLines.isEmpty
            ? output.trimmingCharacters(in: .whitespacesAndNewlines)
            : translationLines.joined(separator: "\n").trimmingCharacters(
                in: .whitespacesAndNewlines)
    }
}
