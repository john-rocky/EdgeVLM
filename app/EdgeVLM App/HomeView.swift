//
// HomeView.swift
// EdgeVLM
//

import SwiftUI

// MARK: - Task Destination

enum TaskDestination: CaseIterable, Hashable {
    case camera, chat, detect, segment, translate, narrate
    case video, screen, compare, extract, ar

    var name: String {
        switch self {
        case .camera: "Camera"
        case .chat: "Chat"
        case .detect: "Detect"
        case .segment: "Segment"
        case .translate: "Translate"
        case .narrate: "Narrate"
        case .video: "Video"
        case .screen: "Screen"
        case .compare: "Compare"
        case .extract: "Extract"
        case .ar: "AR"
        }
    }

    var icon: String {
        switch self {
        case .camera: "camera.fill"
        case .chat: "bubble.left.and.bubble.right"
        case .detect: "viewfinder"
        case .segment: "wand.and.stars"
        case .translate: "character.book.closed"
        case .narrate: "speaker.wave.2"
        case .video: "film"
        case .screen: "rectangle.dashed"
        case .compare: "square.split.2x1"
        case .extract: "doc.text.magnifyingglass"
        case .ar: "arkit"
        }
    }

    var description: String {
        switch self {
        case .camera: "Live image description"
        case .chat: "Multi-turn conversation"
        case .detect: "Object detection"
        case .segment: "Smart segmentation"
        case .translate: "Real-time translation"
        case .narrate: "Audio narration"
        case .video: "Caption & search"
        case .screen: "Screenshot analysis"
        case .compare: "Image comparison"
        case .extract: "Data extraction"
        case .ar: "AR annotation"
        }
    }

    var color: Color {
        switch self {
        case .camera: .blue
        case .chat: .indigo
        case .detect: .orange
        case .segment: .purple
        case .translate: .teal
        case .narrate: .cyan
        case .video: .red
        case .screen: .green
        case .compare: .mint
        case .extract: .yellow
        case .ar: .gray
        }
    }
}

// MARK: - Home View

struct HomeView: View {
    var model: EdgeVLMModel

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private struct TaskSection: Identifiable {
        let id = UUID()
        let title: String
        let tasks: [TaskDestination]
    }

    private var sections: [TaskSection] {
        var result = [
            TaskSection(title: "Live Camera", tasks: [.camera, /* .detect, */ .segment, .translate, .narrate]),
            TaskSection(title: "Photo & Screen", tasks: [.chat, .screen, .compare, .extract]),
            TaskSection(title: "Video", tasks: [.video]),
        ]
        #if os(iOS)
        result.append(TaskSection(title: "Augmented Reality", tasks: [.ar]))
        #endif
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(sections) { section in
                    taskSection(section)
                }
            }
            .padding()
        }
        .background {
            #if os(iOS)
            Color(.systemGroupedBackground).ignoresSafeArea()
            #elseif os(macOS)
            Color(.windowBackgroundColor).ignoresSafeArea()
            #endif
        }
        .navigationTitle("EdgeVLM")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .navigationDestination(for: TaskDestination.self) { destination in
            destinationView(for: destination)
        }
    }

    private func taskSection(_ section: TaskSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.horizontal, 4)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(section.tasks, id: \.self) { destination in
                    NavigationLink(value: destination) {
                        TaskCardView(destination: destination)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func destinationView(for destination: TaskDestination) -> some View {
        switch destination {
        case .camera: ContentView(model: model)
        case .chat: ConversationView(model: model)
        case .detect: DetectionView(model: model)
        case .segment: SmartSegmentView(model: model)
        case .translate: TranslationView(model: model)
        case .narrate: NarrationView(model: model)
        case .video: VideoCaptionView(model: model)
        case .screen: ScreenAnalysisView(model: model)
        case .compare: ImageCompareView(model: model)
        case .extract: DataExtractView(model: model)
        case .ar: ARAnnotationView(model: model)
        }
    }
}

// MARK: - Task Card View

struct TaskCardView: View {
    let destination: TaskDestination

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(destination.color.opacity(0.12))
                    .frame(width: 48, height: 48)

                Image(systemName: destination.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(destination.color)
            }

            VStack(spacing: 2) {
                Text(destination.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(destination.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        }
    }
}

#Preview {
    NavigationStack {
        HomeView(model: EdgeVLMModel())
    }
}
