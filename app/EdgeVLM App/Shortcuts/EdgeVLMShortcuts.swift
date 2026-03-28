//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import AppIntents

struct EdgeVLMShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AnalyzeImageIntent(),
            phrases: [
                "Analyze image with \(.applicationName)",
                "Describe image with \(.applicationName)",
            ],
            shortTitle: "Analyze Image",
            systemImageName: "eye"
        )
        AppShortcut(
            intent: ReadTextIntent(),
            phrases: [
                "Read text with \(.applicationName)",
                "Extract text with \(.applicationName)",
            ],
            shortTitle: "Read Text",
            systemImageName: "doc.text.viewfinder"
        )
    }
}
