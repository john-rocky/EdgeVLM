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
                    .tabItem { Label("Camera", systemImage: "camera.fill") }
                DetectionView(model: model)
                    .tabItem { Label("Detect", systemImage: "viewfinder") }
            }
        }
    }
}
