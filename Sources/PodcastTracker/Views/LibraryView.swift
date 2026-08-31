import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var mediaStore = LocalMediaStore.shared
    @State private var schedulingPodcast: Podcast?

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
                            Button(podcast.scheduledAt == nil ? "Schedule" : "Reschedule") { schedulingPodcast = podcast }
                            downloadMenu(for: podcast)
                            Divider()
                            Button("Delete", role: .destructive) { viewModel.removePodcast(podcast) }
                        }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .sheet(item: $schedulingPodcast) { podcast in
            SchedulePodcastSheet(podcast: podcast, initialDate: podcast.scheduledAt ?? Date().addingTimeInterval(60 * 60))
                .environmentObject(viewModel)
        }
    }

    private var filterBar: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
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
                    }.padding(.horizontal, 16).padding(.top, 12)
                }.scrollIndicators(.hidden)
                if !viewModel.collections.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            Label("Collections", systemImage: "rectangle.stack")
                                .font(.caption).foregroundStyle(.secondary)
                            if viewModel.selectedCollectionID == nil {
                                Button("All Collections") { viewModel.selectedCollectionID = nil }.buttonStyle(.glassProminent)
                            } else {
                                Button("All Collections") { viewModel.selectedCollectionID = nil }.buttonStyle(.glass)
                            }
                            ForEach(viewModel.collections.sorted(by: { $0.sortOrder < $1.sortOrder })) { collection in
                                if viewModel.selectedCollectionID == collection.id {
                                    Button(collection.title) { viewModel.selectedCollectionID = nil }.buttonStyle(.glassProminent)
                                } else {
                                    Button(collection.title) { viewModel.selectedCollectionID = collection.id }.buttonStyle(.glass)
                                }
                            }
                        }.padding(.horizontal, 16).padding(.bottom, 12)
                    }.scrollIndicators(.hidden)
                }
            }
        }
    }

    @ViewBuilder
    private func downloadMenu(for podcast: Podcast) -> some View {
        switch mediaStore.state(for: podcast.youtubeVideoId) {
        case .notDownloaded, .failed:
            Button("Download") { Task { _ = try? await viewModel.download(podcast) } }
        case .queued, .downloading:
            Button("Cancel Download") { viewModel.cancelDownload(podcast) }
        case .downloaded:
            Button("Delete Download", role: .destructive) { viewModel.deleteDownload(podcast) }
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
    @ObservedObject private var mediaStore = LocalMediaStore.shared
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
                    if let scheduledAt = podcast.scheduledAt {
                        Label(scheduledAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar.badge.clock")
                            .foregroundStyle(.orange)
                    }
                    downloadStatus
                }.font(.caption).foregroundStyle(.secondary)
                if podcast.hasProgress { ProgressView(value: podcast.progressPercentage).frame(maxWidth: 360) }
            }
            Spacer()
            downloadButton
            Button("Open", systemImage: "chevron.right") { viewModel.selectPodcast(podcast) }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
        }.padding(.vertical, 8)
    }

    @ViewBuilder
    private var downloadButton: some View {
        switch mediaStore.state(for: podcast.youtubeVideoId) {
        case .notDownloaded, .failed:
            Button("Download", systemImage: "arrow.down.circle") {
                Task { _ = try? await viewModel.download(podcast) }
            }
            .labelStyle(.iconOnly).buttonStyle(.borderless)
        case .queued, .downloading:
            Button("Cancel Download", systemImage: "xmark.circle") { viewModel.cancelDownload(podcast) }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
        case .downloaded:
            Button("Delete Download", systemImage: "checkmark.circle.fill") { viewModel.deleteDownload(podcast) }
                .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var downloadStatus: some View {
        switch mediaStore.state(for: podcast.youtubeVideoId) {
        case .notDownloaded:
            EmptyView()
        case .queued:
            Label("Queued", systemImage: "clock")
        case .downloading:
            Label("Downloading", systemImage: "arrow.down.circle")
        case .downloaded(let record):
            Label(record.retention.expirationDate == nil ? "Offline" : mediaStore.state(for: podcast.youtubeVideoId).label,
                  systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .failed:
            Label("Download failed", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        }
    }
}
