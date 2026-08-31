import SwiftUI

struct AddPodcastSheet: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case episode = "Single Episode"
        case playlist = "YouTube Playlist"
        var id: String { rawValue }
    }

    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .episode
    @State private var title = ""
    @State private var url = ""
    @State private var categoryID = LearningCategory.generalID
    @State private var playlistPreview: PlaylistPreview?
    @State private var isLoadingPlaylist = false
    @State private var errorMessage: String?
    @State private var importResult: PlaylistImportResult?
    @State private var previewTask: Task<Void, Never>?

    private var videoID: String? { Podcast.extractVideoId(from: url) }
    private var canSaveEpisode: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && videoID != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Add", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if mode == .episode { episodeForm } else { playlistForm }

                Section("Category") {
                    Picker("Learning Category", selection: $categoryID) {
                        ForEach(viewModel.categories) { category in
                            Label(category.name, systemImage: category.symbolName).tag(category.id)
                        }
                    }
                    Text("Playlist imports become a separate Collection. This Category is applied only to newly added episodes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(mode == .episode ? "Add Episode" : "Import Playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { confirmationButton }
            }
        }
        .frame(width: 620, height: mode == .playlist ? 560 : 390)
        .onAppear {
            if viewModel.category(for: categoryID) == nil {
                categoryID = viewModel.categories.first?.id ?? LearningCategory.generalID
            }
        }
        .onChange(of: mode) { _, _ in resetPlaylistState() }
        .onChange(of: url) { _, _ in
            if mode == .playlist { playlistPreview = nil; importResult = nil; errorMessage = nil }
        }
        .onDisappear { previewTask?.cancel() }
    }

    private var episodeForm: some View {
        Section("Episode") {
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            TextField("YouTube URL", text: $url).textFieldStyle(.roundedBorder)
            if !url.isEmpty && videoID == nil {
                Label("Enter a valid YouTube URL or video ID.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Text("Adding an episode never downloads it.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var playlistForm: some View {
        Section("Playlist") {
            TextField("YouTube playlist URL", text: $url).textFieldStyle(.roundedBorder)
            if isLoadingPlaylist {
                HStack { ProgressView(); Text("Loading playlist metadata…") }
            }
            if let preview = playlistPreview {
                VStack(alignment: .leading, spacing: 8) {
                    Text(preview.title).font(.headline)
                    LabeledContent("Available episodes", value: "\(preview.episodes.count)")
                    LabeledContent("Unavailable or private", value: "\(preview.unavailableCount)")
                    Text("No videos will be downloaded during import.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let result = importResult {
                Label("Added \(result.added), reused \(result.reused), skipped \(result.skipped).", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var confirmationButton: some View {
        if mode == .episode {
            Button("Add") {
                viewModel.addPodcast(title: title, url: url, categoryID: categoryID)
                dismiss()
            }
            .buttonStyle(.glassProminent)
            .disabled(!canSaveEpisode)
        } else if importResult != nil {
            Button("Done") { dismiss() }.buttonStyle(.glassProminent)
        } else if let preview = playlistPreview {
            Button("Import \(preview.episodes.count)") {
                importResult = viewModel.importPlaylist(preview, categoryID: categoryID)
                playlistPreview = nil
            }
            .buttonStyle(.glassProminent)
        } else {
            Button("Preview") { loadPlaylist() }
                .buttonStyle(.glassProminent)
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingPlaylist)
        }
    }

    private func loadPlaylist() {
        previewTask?.cancel()
        isLoadingPlaylist = true
        errorMessage = nil
        importResult = nil
        let input = url
        previewTask = Task {
            do {
                playlistPreview = try await PlaylistImporter.preview(url: input)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoadingPlaylist = false
        }
    }

    private func resetPlaylistState() {
        previewTask?.cancel()
        playlistPreview = nil
        importResult = nil
        errorMessage = nil
        isLoadingPlaylist = false
        url = ""
        title = ""
    }
}
