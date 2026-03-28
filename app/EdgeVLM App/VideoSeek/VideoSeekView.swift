//
// VideoSeekView.swift
// EdgeVLM
//
// Main view for the Video Seek feature: import a video, index frames,
// search by natural language, and browse matching results.
//

import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct VideoSeekView: View {
    var model: EdgeVLMModel

    @State private var engine = VideoIndexEngine()
    @State private var searchQuery = ""
    @State private var searchResults: [IndexEntry] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var videoURL: URL?
    @State private var videoFileName: String?

    // File importer
    @State private var isShowingFileImporter = false

    // Photos picker
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                // Video import section
                importSection

                // Indexing status section
                if engine.isIndexing {
                    indexingSection
                }

                // Search section (visible after indexing)
                if !engine.videoIndex.entries.isEmpty && !engine.isIndexing {
                    searchSection
                    resultsSection
                }
            }
            #if os(iOS)
            .listSectionSpacing(0)
            #elseif os(macOS)
            .padding()
            #endif
            .navigationTitle("Video Seek")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                if let newItem {
                    handlePhotosPickerItem(newItem)
                }
            }
            .task {
                await model.load()
            }
            .onChange(of: searchQuery) { _, newValue in
                performSearch(newValue)
            }
        }
    }

    // MARK: - Search

    private func performSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            searchResults = engine.videoIndex.entries
            isSearching = false
            return
        }

        // Show instant keyword results first
        searchResults = engine.videoIndex.search(query: trimmed)
        isSearching = true

        // Then expand with Foundation Models for broader matching
        searchTask = Task {
            let expanded = await engine.videoIndex.semanticSearch(query: trimmed)
            if !Task.isCancelled {
                searchResults = expanded
                isSearching = false
            }
        }
    }

    // MARK: - Import Section

    private var importSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                if let videoFileName {
                    HStack {
                        Image(systemName: "film")
                            .foregroundStyle(.secondary)
                        Text(videoFileName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        isShowingFileImporter = true
                    } label: {
                        Label("Browse Files", systemImage: "folder")
                    }

                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .videos
                    ) {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                    }
                }
                #if os(macOS)
                .buttonStyle(.bordered)
                #endif

                if videoURL != nil && !engine.isIndexing {
                    Button {
                        if let url = videoURL {
                            engine.indexVideo(url: url, model: model)
                        }
                    } label: {
                        Label("Index Video", systemImage: "magnifyingglass.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(engine.isIndexing)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Video")
                #if os(macOS)
                .font(.headline)
                .padding(.bottom, 2)
                #endif
        }
    }

    // MARK: - Indexing Section

    private var indexingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ProgressView(value: engine.progress)
                    Text("\(Int(engine.progress * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Text(engine.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Cancel", role: .destructive) {
                    engine.cancel()
                }
                .font(.caption)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Indexing")
                #if os(macOS)
                .font(.headline)
                .padding(.bottom, 2)
                #endif
        }
    }

    // MARK: - Search Section

    private var searchSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search frames (e.g., \"dog appears\")", text: $searchQuery)
                        .textFieldStyle(.plain)
                }

                if isSearching {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Expanding search...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !engine.statusMessage.isEmpty {
                    Text(engine.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Search")
                #if os(macOS)
                .font(.headline)
                .padding(.bottom, 2)
                #endif
        }
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        Section {
            if searchResults.isEmpty {
                Text("No matching frames found.")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(searchResults) { entry in
                    NavigationLink(destination: SeekResultView(entry: entry)) {
                        resultRow(entry: entry)
                    }
                }
            }
        } header: {
            HStack {
                Text("Results")
                Spacer()
                Text("\(searchResults.count) frames")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #if os(macOS)
            .font(.headline)
            .padding(.bottom, 2)
            #endif
        }
    }

    private func resultRow(entry: IndexEntry) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            Image(decorative: entry.thumbnail, scale: 1.0)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.formattedTimestamp)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()

                Text(entry.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Import Handlers

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            if url.startAccessingSecurityScopedResource() {
                videoURL = url
                videoFileName = url.lastPathComponent
            }
        case .failure(let error):
            print("File import error: \(error.localizedDescription)")
        }
    }

    private func handlePhotosPickerItem(_ item: PhotosPickerItem) {
        Task {
            // Load the video as a file URL via transferable
            if let movie = try? await item.loadTransferable(type: VideoTransferable.self) {
                videoURL = movie.url
                videoFileName = movie.url.lastPathComponent
            }
        }
    }
}

/// Transferable wrapper to load a video from PhotosPicker as a temporary file URL.
struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            // Copy to a temporary location to ensure it persists
            let tempDir = FileManager.default.temporaryDirectory
            let destURL = tempDir.appendingPathComponent(
                received.file.lastPathComponent
            )
            // Remove existing file at destination if any
            try? FileManager.default.removeItem(at: destURL)
            try FileManager.default.copyItem(at: received.file, to: destURL)
            return Self(url: destURL)
        }
    }
}
