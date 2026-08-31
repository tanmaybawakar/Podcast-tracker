import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            if viewModel.filteredPodcasts.isEmpty {
                ContentUnavailableView(
                    viewModel.podcasts.isEmpty ? "Your library is empty" : "No matching episodes",
                    systemImage: "books.vertical",
                    description: Text(viewModel.podcasts.isEmpty ? "Add a YouTube episode you genuinely want to learn from." : "Try a different search or category.")
                )
            } else {
                List(viewModel.filteredPodcasts) { podcast in
                    PodcastLibraryRow(podcast: podcast)
                        .environmentObject(viewModel)
                        .contentShape(.rect)
                        .onTapGesture { viewModel.selectPodcast(podcast) }
                        .contextMenu {
                            Button("Open") { viewModel.selectPodcast(podcast) }
                            Button("Mark Complete") { viewModel.markCompleted(podcast) }
                            Divider()
                            Button("Delete", role: .destructive) { viewModel.removePodcast(podcast) }
                        }
                }
                .listStyle(.inset)
            }
        }
    }

    private var filterBar: some View {
        GlassEffectContainer(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if viewModel.selectedCategoryID == nil {
                        Button("All") { viewModel.selectedCategoryID = nil }.buttonStyle(.glassProminent)
                    } else {
                        Button("All") { viewModel.selectedCategoryID = nil }.buttonStyle(.glass)
                    }
                    ForEach(viewModel.categories) { category in
                        if viewModel.selectedCategoryID == category.id {
                            categoryButton(category).buttonStyle(.glassProminent).tint(category.color)
                        } else {
                            categoryButton(category).buttonStyle(.glass).tint(category.color)
                        }
                    }
                }.padding(16)
            }.scrollIndicators(.hidden)
        }
    }

    private func categoryButton(_ category: LearningCategory) -> some View {
        Button { viewModel.selectedCategoryID = viewModel.selectedCategoryID == category.id ? nil : category.id } label: {
            Label(category.name, systemImage: category.symbolName)
        }
    }
}

private struct PodcastLibraryRow: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let podcast: Podcast
    var category: LearningCategory? { viewModel.category(for: podcast.categoryID) }

    var body: some View {
        HStack(spacing: 16) {
            AsyncImage(url: podcast.thumbnailURL.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() }
                placeholder: { Rectangle().fill(.quaternary).overlay { Image(systemName: "play.rectangle") } }
                .frame(width: 132, height: 74).clipShape(.rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 7) {
                Text(podcast.title).font(.headline).lineLimit(2)
                HStack(spacing: 10) {
                    if let category { Label(category.name, systemImage: category.symbolName).foregroundStyle(category.color) }
                    if podcast.isCompleted { Label("Completed", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    else if podcast.hasProgress { Text("\(Int(podcast.progressPercentage * 100))% watched") }
                }.font(.caption).foregroundStyle(.secondary)
                if podcast.hasProgress { ProgressView(value: podcast.progressPercentage).frame(maxWidth: 360) }
            }
            Spacer()
            Button("Open", systemImage: "chevron.right") { viewModel.selectPodcast(podcast) }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
        }.padding(.vertical, 8)
    }
}
