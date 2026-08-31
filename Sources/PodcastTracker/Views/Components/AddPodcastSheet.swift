import SwiftUI

struct AddPodcastSheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var url = ""
    @State private var categoryID = LearningCategory.generalID

    private var videoID: String? { Podcast.extractVideoId(from: url) }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && videoID != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Episode") {
                    TextField("Title", text: $title).textFieldStyle(.roundedBorder)
                    TextField("YouTube URL", text: $url).textFieldStyle(.roundedBorder)
                    if !url.isEmpty && videoID == nil { Label("Enter a valid YouTube URL or video ID.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
                Section("Category") {
                    Picker("Category", selection: $categoryID) {
                        ForEach(viewModel.categories) { category in Label(category.name, systemImage: category.symbolName).tag(category.id) }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Episode")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { viewModel.addPodcast(title: title, url: url, categoryID: categoryID); dismiss() }
                        .buttonStyle(.glassProminent).disabled(!canSave)
                }
            }
        }
        .frame(width: 520, height: 340)
        .onAppear { if viewModel.category(for: categoryID) == nil { categoryID = viewModel.categories.first?.id ?? LearningCategory.generalID } }
    }
}
