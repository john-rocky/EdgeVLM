//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import SwiftUI

@main
struct EdgeVLMApp: App {
    @State private var model = EdgeVLMModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView(model: model)
                    .tabItem {
                        Label("Camera", systemImage: "camera.fill")
                    }
                ConversationView(model: model)
                    .tabItem {
                        Label("Chat", systemImage: "bubble.left.and.bubble.right")
                    }
                DetectionView(model: model)
                    .tabItem {
                        Label("Detect", systemImage: "viewfinder")
                    }
                SmartSegmentView(model: model)
                    .tabItem {
                        Label("Segment", systemImage: "wand.and.stars")
                    }
                TranslationView(model: model)
                    .tabItem {
                        Label("Translate", systemImage: "character.book.closed")
                    }
                NarrationView(model: model)
                    .tabItem {
                        Label("Narrate", systemImage: "speaker.wave.2")
                    }
                VideoCaptionView(model: model)
                    .tabItem {
                        Label("Caption", systemImage: "film")
                    }
                VideoSeekView(model: model)
                    .tabItem {
                        Label("Seek", systemImage: "film.circle")
                    }
                ScreenAnalysisView(model: model)
                    .tabItem {
                        Label("Screen", systemImage: "rectangle.dashed")
                    }
                ImageCompareView(model: model)
                    .tabItem {
                        Label("Compare", systemImage: "square.split.2x1")
                    }
                DataExtractView(model: model)
                    .tabItem {
                        Label("Extract", systemImage: "doc.text.magnifyingglass")
                    }
                ARAnnotationView(model: model)
                    .tabItem {
                        Label("AR", systemImage: "arkit")
                    }
            }
        }
    }
}
