//
// ConversationMessage.swift
// EdgeVLM App
//

import Foundation

/// A single message in a multi-turn conversation about an image.
struct ConversationMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String

    enum Role {
        case user
        case assistant
    }
}
