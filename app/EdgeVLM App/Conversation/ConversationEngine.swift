//
// ConversationEngine.swift
// EdgeVLM App
//

import CoreImage
import Foundation
import MLXLMCommon

/// Manages multi-turn conversation state for an image.
/// Accumulates question/answer history and builds a combined prompt
/// so the VLM can reference prior context on each new question.
@Observable
@MainActor
class ConversationEngine {

    /// The full conversation history for the current image.
    var messages: [ConversationMessage] = []

    /// The captured image that all questions reference.
    var capturedImage: CIImage?

    /// Whether the engine is currently waiting for a model response.
    var isGenerating: Bool = false

    /// Ask a new question about the captured image.
    /// Builds a combined prompt from conversation history, sends it
    /// together with the image, and appends both the user question
    /// and the assistant response to the history.
    func ask(question: String, model: EdgeVLMModel) async {
        guard let image = capturedImage else { return }
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)

        // Append the user message immediately so the UI updates
        messages.append(ConversationMessage(role: .user, text: trimmedQuestion))
        isGenerating = true

        // Build the combined prompt with conversation history
        let combinedPrompt = buildPrompt(newQuestion: trimmedQuestion)

        let userInput = UserInput(
            prompt: .text(combinedPrompt),
            images: [.ciImage(image)]
        )

        do {
            let response = try await model.generateCaption(userInput)
            let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
            messages.append(ConversationMessage(role: .assistant, text: trimmedResponse))
        } catch {
            messages.append(ConversationMessage(role: .assistant, text: "Error: \(error.localizedDescription)"))
        }

        isGenerating = false
    }

    /// Clear all conversation history and the captured image.
    func reset() {
        messages = []
        capturedImage = nil
        isGenerating = false
    }

    // MARK: - Private

    /// Build a combined prompt that includes all prior Q&A pairs
    /// followed by the new question so the VLM has full context.
    private func buildPrompt(newQuestion: String) -> String {
        // If this is the first question, just send it directly
        if messages.count <= 1 {
            return "\(newQuestion)\nAnswer briefly."
        }

        // Build history from all messages except the last one (the new user question)
        var historyLines: [String] = []
        let priorMessages = messages.dropLast()
        for message in priorMessages {
            switch message.role {
            case .user:
                historyLines.append("Q: \(message.text)")
            case .assistant:
                historyLines.append("A: \(message.text)")
            }
        }

        let history = historyLines.joined(separator: "\n")

        return """
            Previous conversation:
            \(history)

            New question: \(newQuestion)
            Answer briefly.
            """
    }
}
