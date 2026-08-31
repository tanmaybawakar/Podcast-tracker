import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PlayerView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var mediaStore = LocalMediaStore.shared
    let podcast: Podcast
    @StateObject private var playerController = PlayerController()
    @State private var useNativePlayer = true
    @State private var playbackFailed = false
    @State private var playbackAttemptID = UUID()
    @State private var nativeRetryCount = 0
    @State private var showFileImporter = false
    @State private var showPasteSheet = false
    @State private var playbackSource: NativePlaybackSource?
    @State private var isPreparingDownload = false
    @State private var playbackChoiceError: String?
    @State private var showScheduleSheet = false

    private var currentPodcast: Podcast { viewModel.podcasts.first(where: { $0.id == podcast.id }) ?? podcast }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if playbackSource == nil {
                    playbackChoiceView
                } else if playbackFailed {
                    unavailableView
                } else if useNativePlayer {
                    let attemptID = playbackAttemptID
                    NativePlayerView(
                        videoId: currentPodcast.youtubeVideoId,
                        startPosition: currentPodcast.lastPlaybackPosition,
                        reloadID: attemptID,
                        source: playbackSource ?? .stream,
                        controller: playerController,
                        onTimeUpdate: { viewModel.updatePlaybackPosition(for: currentPodcast.id, position: $0) },
                        onDurationReady: { viewModel.updateDuration(for: currentPodcast.id, duration: $0) },
                        onPlayStateChange: handlePlayStateChange,
                        onFailure: { handleNativeFailure(for: attemptID) }
                    )
                    .id(attemptID)
                } else {
                    YouTubeWebView(
                        videoId: currentPodcast.youtubeVideoId,
                        startPosition: currentPodcast.lastPlaybackPosition,
                        controller: playerController,
                        onTimeUpdate: { viewModel.updatePlaybackPosition(for: currentPodcast.id, position: $0) },
                        onDurationReady: { viewModel.updateDuration(for: currentPodcast.id, duration: $0) },
                        onPlayStateChange: handlePlayStateChange,
                        onError: { playbackFailed = true }
                    )
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let commitment = viewModel.activeCommitment {
                CommitmentBar(
                    commitment: commitment,
                    isPlaying: viewModel.isTracking,
                    isStarting: playerController.isPlaybackStartPending
                )
                    .environmentObject(viewModel)
            }

            HStack(spacing: 14) {
                if let category = viewModel.category(for: currentPodcast.categoryID) {
                    Label(category.name, systemImage: category.symbolName).foregroundStyle(category.color)
                }
                Spacer()
                if currentPodcast.isCompleted { Label("Completed", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                else { Button("Mark Complete", systemImage: "checkmark.circle") { viewModel.markCompleted(currentPodcast) }.buttonStyle(.glass) }
                Button(currentPodcast.scheduledAt == nil ? "Schedule" : "Reschedule", systemImage: "calendar.badge.clock") {
                    showScheduleSheet = true
                }
                .buttonStyle(.glass)
                downloadAction
            }
            .font(.subheadline).padding(16)
        }
        .background(.black.opacity(0.92))
        .overlay(alignment: .bottom) {
            if let commitment = viewModel.completedCommitment, commitment.podcastID == currentPodcast.id {
                CommitmentWin(commitment: commitment)
                    .environmentObject(viewModel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
        .inspector(isPresented: $viewModel.inspectorPresented) {
            PlayerInspector(
                podcast: currentPodcast, playerController: playerController,
                showFileImporter: $showFileImporter, showPasteSheet: $showPasteSheet
            )
            .environmentObject(viewModel)
            .inspectorColumnWidth(min: 330, ideal: 400, max: 520)
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.plainText, .data]) { result in
            guard case .success(let url) = result, url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: url),
               let document = try? TranscriptImporter.document(data: data, fileExtension: url.pathExtension, podcastID: currentPodcast.id) {
                viewModel.generateSummary(for: currentPodcast, transcript: document)
            }
        }
        .sheet(isPresented: $showPasteSheet) { PasteTranscriptSheet(podcast: currentPodcast) }
        .sheet(isPresented: $showScheduleSheet) {
            SchedulePodcastSheet(podcast: currentPodcast, initialDate: currentPodcast.scheduledAt ?? Date().addingTimeInterval(60 * 60))
                .environmentObject(viewModel)
        }
        .task(id: currentPodcast.id) {
            resetPlayback()
            chooseInitialPlaybackSource()
            startRequestedPlaybackIfNeeded()
        }
        .onChange(of: viewModel.playbackStartRequest) { _, request in
            guard request?.targets(currentPodcast.id) == true else { return }
            startRequestedPlaybackIfNeeded()
        }
        .onDisappear {
            if viewModel.isTracking, viewModel.selectedPodcast?.id == currentPodcast.id { viewModel.stopTracking() }
        }
    }

    private func startRequestedPlaybackIfNeeded() {
        guard viewModel.consumePlaybackStartRequest(for: currentPodcast.id) else { return }
        playerController.requestPlaybackStart()
    }

    private func handlePlayStateChange(_ isPlaying: Bool) {
        if isPlaying { nativeRetryCount = 0 }
        playerController.playerStateDidChange(isPlaying: isPlaying)
        viewModel.handlePlaybackState(podcast: currentPodcast, isPlaying: isPlaying)
    }

    private func handleNativeFailure(for attemptID: UUID) {
        guard useNativePlayer, playbackAttemptID == attemptID else { return }
        guard nativeRetryCount < 2 else {
            if playbackSource == .stream { useNativePlayer = false }
            else { playbackFailed = true }
            return
        }

        nativeRetryCount += 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, useNativePlayer, playbackAttemptID == attemptID else { return }
            playbackAttemptID = UUID()
        }
    }

    private func resetPlayback() {
        nativeRetryCount = 0
        playbackFailed = false
        useNativePlayer = true
        playbackAttemptID = UUID()
    }

    private func chooseInitialPlaybackSource() {
        playbackChoiceError = nil
        if mediaStore.cachedPlayableURL(videoId: currentPodcast.youtubeVideoId) != nil {
            playbackSource = .local
        } else {
            playbackSource = nil
        }
    }

    private func stream() {
        playbackChoiceError = nil
        useNativePlayer = true
        playbackFailed = false
        nativeRetryCount = 0
        playbackSource = .stream
        playbackAttemptID = UUID()
    }

    private func downloadAndPlay() {
        guard !isPreparingDownload else { return }
        isPreparingDownload = true
        playbackChoiceError = nil
        Task {
            do {
                _ = try await viewModel.download(currentPodcast)
                useNativePlayer = true
                playbackFailed = false
                nativeRetryCount = 0
                playbackSource = .local
                playbackAttemptID = UUID()
            } catch is CancellationError {
                playbackChoiceError = nil
            } catch {
                playbackChoiceError = error.localizedDescription
            }
            isPreparingDownload = false
        }
    }

    @ViewBuilder
    private var downloadAction: some View {
        switch mediaStore.state(for: currentPodcast.youtubeVideoId) {
        case .notDownloaded, .failed:
            Button("Download", systemImage: "arrow.down.circle") { downloadAndPlay() }.buttonStyle(.glass)
        case .queued, .downloading:
            Button("Cancel Download", systemImage: "xmark.circle") { viewModel.cancelDownload(currentPodcast) }.buttonStyle(.glass)
        case .downloaded:
            Button("Delete Download", systemImage: "trash", role: .destructive) {
                viewModel.deleteDownload(currentPodcast)
                playbackSource = nil
            }
            .buttonStyle(.glass)
        }
    }

    private var playbackChoiceView: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(isPreparingDownload ? "Downloading for offline playback…" : "How do you want to play this episode?")
                .font(.headline)
            if isPreparingDownload {
                ProgressView().controlSize(.large)
                if let bytes = mediaStore.activeDownloadedBytes[currentPodcast.youtubeVideoId], bytes > 0 {
                    Text("\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) downloaded")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("\(mediaStore.settings.quality.title) · \(ByteCountFormatter.string(fromByteCount: mediaStore.remainingStorageBytes, countStyle: .file)) available")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Cancel Download") { viewModel.cancelDownload(currentPodcast) }
            } else {
                Text("Streaming uses no permanent storage. Downloading makes the complete video available offline.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button("Stream", systemImage: "play.fill") { stream() }.buttonStyle(.glassProminent)
                    Button("Download & Play", systemImage: "arrow.down.circle") { downloadAndPlay() }.buttonStyle(.glass)
                    Button("Cancel") { viewModel.selectedPodcast = nil }.buttonStyle(.glass)
                }
            }
            if let playbackChoiceError {
                Text(playbackChoiceError).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .foregroundStyle(.white)
    }

    private var unavailableView: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("This video can't be played in the app")
                .font(.headline)
            Text("YouTube is blocking in-app playback for this video.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Retry in PodTrackio", systemImage: "arrow.clockwise") {
                    resetPlayback()
                }
                .buttonStyle(.glassProminent)
                Button("Watch on YouTube", systemImage: "arrow.up.forward") {
                    if let url = URL(string: "https://www.youtube.com/watch?v=\(currentPodcast.youtubeVideoId)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .foregroundStyle(.white)
    }
}

private struct CommitmentBar: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let commitment: FocusCommitment
    let isPlaying: Bool
    let isStarting: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: commitment.cue.symbolName)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(statusTitle)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(statusDetail)
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                ProgressView(value: commitment.progress)
                    .accessibilityLabel("Learning commitment progress")
                    .accessibilityValue("\(Int(commitment.progress * 100)) percent")
            }
            Button("Cancel commitment", systemImage: "xmark") { viewModel.cancelActiveCommitment() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.background.secondary)
    }

    private var statusTitle: String {
        if isPlaying { return "Useful time in progress" }
        if isStarting { return "Starting your learning block…" }
        return "Your \(commitment.targetMinutes)-minute promise is ready"
    }

    private var statusDetail: String {
        if isPlaying { return "\(Int(ceil(commitment.remainingSeconds / 60))) min left" }
        return isStarting ? "Opening at your last position" : "Press Play to begin"
    }
}

private struct CommitmentWin: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let commitment: FocusCommitment

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text("The video can keep playing. Extend only if you want the next small win.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("+5") { viewModel.extendCommitment(by: 5) }.buttonStyle(.glassProminent)
                Button("+10") { viewModel.extendCommitment(by: 10) }.buttonStyle(.glass)
                Button("Done") { viewModel.dismissCompletedCommitment() }.buttonStyle(.glass)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        }
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        if commitment.cue.isDistraction {
            return "\(commitment.targetMinutes) minutes reclaimed from \(commitment.cue.title.lowercased())"
        }
        return "You kept your \(commitment.targetMinutes)-minute promise"
    }
}

private struct PlayerInspector: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let podcast: Podcast
    let playerController: PlayerController
    @Binding var showFileImporter: Bool
    @Binding var showPasteSheet: Bool

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $viewModel.inspectorMode) {
                ForEach(PlayerInspectorMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).padding()
            Divider()
            switch viewModel.inspectorMode {
            case .summary: SummaryInspector(podcast: podcast, playerController: playerController, showFileImporter: $showFileImporter, showPasteSheet: $showPasteSheet)
            case .notes: NotesInspector(podcast: podcast)
            case .chat: TranscriptChatInspector(podcast: podcast)
            }
        }
        .background(.background)
    }
}

private struct SummaryInspector: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let podcast: Podcast
    let playerController: PlayerController
    @Binding var showFileImporter: Bool
    @Binding var showPasteSheet: Bool

    var body: some View {
        if let summary = viewModel.summary(for: podcast.id) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text(summary.brief).font(.body).textSelection(.enabled).lineSpacing(4)
                    if summary.sections.isEmpty {
                        legacySections(summary)
                    } else {
                        ForEach(summary.sections) { section in
                            SummarySection(section.title, symbol: "text.book.closed") {
                                if let introduction = section.introduction { Text(introduction).foregroundStyle(.secondary).textSelection(.enabled) }
                                ForEach(Array(section.points.enumerated()), id: \.element.id) { index, point in
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text("\(index + 1)").foregroundStyle(.secondary).monospacedDigit()
                                            Text(point.title).font(.headline)
                                            Spacer()
                                            if let seconds = point.timestampSeconds {
                                                Button(seconds.formattedTimestamp) { playerController.seek(to: seconds) }.buttonStyle(.glass).controlSize(.small)
                                            }
                                        }
                                        Text(point.explanation).foregroundStyle(.secondary).textSelection(.enabled)
                                    }.padding(.vertical, 5)
                                }
                            }
                        }
                    }
                    if !summary.actionPlan.isEmpty {
                        SummarySection("Try this", symbol: "checklist") {
                            ForEach(summary.actionPlan) { action in
                                Toggle(isOn: Binding(
                                    get: { viewModel.summary(for: podcast.id)?.actionPlan.first(where: { $0.id == action.id })?.isCompleted ?? false },
                                    set: { _ in viewModel.toggleAction(podcastID: podcast.id, actionID: action.id) }
                                )) { VStack(alignment: .leading, spacing: 3) { Text(action.title).font(.headline); Text(action.detail).font(.caption).foregroundStyle(.secondary) } }
                                .toggleStyle(.checkbox).padding(.vertical, 4)
                            }
                        }
                    }
                    Text("Generated \(summary.generatedAt.formatted(date: .abbreviated, time: .shortened)) · \(summary.model)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }.padding(20)
            }
        } else {
            summaryEmptyState
        }
    }

    @ViewBuilder private func legacySections(_ summary: PodcastSummary) -> some View {
        SummarySection("Key topics", symbol: "timeline.selection") {
            ForEach(Array(summary.keyTopics.enumerated()), id: \.element.id) { index, topic in
                VStack(alignment: .leading, spacing: 5) { HStack { Text("\(index + 1)").foregroundStyle(.secondary); Text(topic.title).font(.headline); Spacer(); if let seconds = topic.timestampSeconds { Button(seconds.formattedTimestamp) { playerController.seek(to: seconds) }.buttonStyle(.glass).controlSize(.small) } }; Text(topic.explanation).foregroundStyle(.secondary).textSelection(.enabled) }.padding(.vertical, 5)
            }
        }
        SummarySection("Major takeaways", symbol: "lightbulb.max") {
            ForEach(summary.majorTakeaways) { takeaway in VStack(alignment: .leading, spacing: 5) { Text(takeaway.title).font(.headline); Text(takeaway.explanation).foregroundStyle(.secondary).textSelection(.enabled) }.padding(12).background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 10)) }
        }
    }

    private var summaryEmptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "text.document.badge.sparkles").font(.system(size: 38)).foregroundStyle(.secondary)
            Text("Turn this episode into a study guide").font(.title3.bold())
            Text(statusCopy).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 330)
            progressControls
            Spacer()
            HStack {
                Button("Paste Transcript") { showPasteSheet = true }
                Button("Import File…") { showFileImporter = true }
            }.buttonStyle(.link)
        }.padding(24)
    }

    private var statusCopy: String {
        switch viewModel.summaryState {
        case .idle, .completed: "PodTrackio fetches a timestamped transcript through TranscriptAPI, then Groq turns it into a study guide."
        case .fetchingTranscript: "Fetching a timestamped transcript from TranscriptAPI…"
        case .fetchingCaptions: "Looking for public captions…"
        case .needsAudioConsent: "No public captions were available. Audio transcription downloads media and consumes Groq credits."
        case .downloadingAudio(let progress): "Downloading the lowest suitable audio stream… \(Int(progress * 100))%"
        case .transcribing(let current, let total): "Transcribing audio chunk \(current) of \(total)…"
        case .synthesizing: "Finding the ideas, frameworks, examples, and actions that are actually in this video…"
        case .needsTranscriptImport(let reason): "Automatic extraction failed: \(reason)"
        case .failed(let message): message
        }
    }

    @ViewBuilder private var progressControls: some View {
        GlassEffectContainer(spacing: 10) {
            switch viewModel.summaryState {
            case .fetchingTranscript, .fetchingCaptions, .downloadingAudio, .transcribing, .synthesizing:
                HStack { ProgressView(); Button("Cancel") { viewModel.cancelSummaryGeneration() }.buttonStyle(.glass) }
            case .needsAudioConsent:
                HStack {
                    Button("Transcribe Audio", systemImage: "waveform") { viewModel.generateSummary(for: podcast, allowAudioTranscription: true) }
                        .buttonStyle(.glassProminent)
                    Button("Import Instead") { showFileImporter = true }.buttonStyle(.glass)
                }
            case .needsTranscriptImport:
                HStack { Button("Paste") { showPasteSheet = true }.buttonStyle(.glassProminent); Button("Import") { showFileImporter = true }.buttonStyle(.glass) }
            default:
                Button("Generate Summary", systemImage: "sparkles") { viewModel.generateSummary(for: podcast) }
                    .buttonStyle(.glassProminent)
            }
        }
    }
}

private struct SummarySection<Content: View>: View {
    let title: String; let symbol: String; @ViewBuilder let content: Content
    init(_ title: String, symbol: String, @ViewBuilder content: () -> Content) { self.title = title; self.symbol = symbol; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.title3.bold())
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NotesInspector: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let podcast: Podcast
    @State private var notes = ""
    var body: some View {
        TextEditor(text: $notes).font(.body).scrollContentBackground(.hidden).padding(16)
            .background(.background)
            .onAppear { notes = podcast.notes }
            .onChange(of: notes) { _, value in viewModel.updateNotes(for: podcast.id, notes: value) }
            .accessibilityLabel("Notes for \(podcast.title)")
    }
}

private struct TranscriptChatInspector: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let podcast: Podcast
    @State private var draft = ""
    @State private var isThinking = false
    @State private var errorMessage: String?
    @State private var responseTask: Task<Void, Never>?
    @AppStorage("quirky.selectedModel") private var selectedModelRaw = QuirkyModel.balanced.rawValue
    @FocusState private var composerFocused: Bool

    private var selectedModel: QuirkyModel { QuirkyModel(rawValue: selectedModelRaw) ?? .balanced }
    private var messages: [QuirkyChatMessage] { viewModel.quirkyMessages(for: podcast.id) }

    var body: some View {
        VStack(spacing: 0) {
            quirkyHeader
            Divider()
            conversation
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            composer
        }
        .onDisappear { responseTask?.cancel() }
    }

    private var quirkyHeader: some View {
        HStack(spacing: 10) {
            QuirkyMark(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Quirky").font(.headline)
                Text("Your transcript mentor").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            modelMenu
            if !messages.isEmpty {
                Button { viewModel.clearQuirkyConversation(for: podcast.id); errorMessage = nil } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("New conversation").disabled(isThinking)
            }
        }.padding(.horizontal, 16).padding(.vertical, 11)
    }

    @ViewBuilder private var conversation: some View {
        if messages.isEmpty {
            ScrollView {
                VStack(spacing: 18) {
                    QuirkyMark(size: 58)
                    VStack(spacing: 6) {
                        Text("What do you want to understand?").font(.title3.bold())
                        Text("Quirky can recover missing steps, challenge an idea, or turn the lesson into something you can actually use.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
                    }
                    VStack(spacing: 8) {
                        QuirkySuggestion(title: "Recover the complete framework", symbol: "list.number", prompt: "Find the main framework or process in this video. Give me every step in order, explain each one, and cite the relevant timestamps.", action: send)
                        QuirkySuggestion(title: "Apply it to one of my projects", symbol: "arrow.triangle.branch", prompt: "Help me apply the strongest lesson from this video to one of my projects. Give me a useful first pass, then ask one question to personalize it.", action: send)
                        QuirkySuggestion(title: "Challenge the speaker's advice", symbol: "checkmark.seal", prompt: "Stress-test the speaker's core advice. What is strong, what depends on assumptions, and where could following it blindly fail?", action: send)
                    }.frame(maxWidth: 470)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 36)
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 18) {
                        ForEach(messages) { message in QuirkyMessageRow(message: message).id(message.id) }
                        if isThinking {
                            HStack(alignment: .center, spacing: 10) {
                                QuirkyMark(size: 28)
                                ProgressView().controlSize(.small)
                                Text("Quirky is thinking with (selectedModel.title.lowercased()) reasoning…").font(.callout).foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }.padding(16).padding(.bottom, 10)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    if let id = messages.last?.id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill").font(.caption).foregroundStyle(.red)
                }
                VStack(spacing: 8) {
                    TextField("Ask Quirky about this video…", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain).lineLimit(1...5).focused($composerFocused).onSubmit { send() }
                    HStack(spacing: 10) {
                        Label(selectedModel.title, systemImage: selectedModel.symbol)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Label("Transcript", systemImage: "text.quote")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button { send() } label: {
                            Image(systemName: "arrow.up").font(.headline).frame(width: 30, height: 30)
                                .background(canSend ? Color.accentColor : Color.secondary.opacity(0.18), in: .circle)
                                .foregroundStyle(canSend ? Color.white : Color.secondary)
                        }.buttonStyle(.plain).disabled(!canSend).keyboardShortcut(.return, modifiers: [.command])
                    }
                }
                .padding(11)
                .background(.regularMaterial, in: .rect(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(composerFocused ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.22), lineWidth: composerFocused ? 1.5 : 1) }
                Text("Grounded in \(podcast.title) · Enter to send").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }.padding(12).background(.background)
        }
    }

    private var modelMenu: some View {
        Menu {
            ForEach(QuirkyModel.allCases) { model in
                Button {
                    selectedModelRaw = model.rawValue
                } label: {
                    Label(model.title, systemImage: model == selectedModel ? "checkmark" : model.symbol)
                }
            }
        } label: {
            Label(selectedModel.title, systemImage: selectedModel.symbol).font(.caption.weight(.medium))
        }
        .menuStyle(.borderlessButton)
        .disabled(isThinking)
        .help(selectedModel.detail)
    }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking }

    private func send(_ suggestedQuestion: String? = nil) {
        let question = (suggestedQuestion ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        let model = selectedModel
        let history = messages.map { ($0.role == .user ? "user" : "assistant", $0.text) }
        draft = ""; errorMessage = nil; viewModel.appendQuirkyMessage(.init(role: .user, text: question, model: nil), podcastID: podcast.id); isThinking = true
        responseTask = Task {
            do {
                let answer = try await viewModel.askTranscriptQuestion(for: podcast, question: question, history: history, model: model)
                guard !Task.isCancelled else { return }
                viewModel.appendQuirkyMessage(.init(role: .quirky, text: answer, model: model), podcastID: podcast.id); isThinking = false
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription; isThinking = false
            }
        }
    }
}

private struct QuirkyMark: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.14))
            Image(systemName: "bubble.left.and.text.bubble.right.fill").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(Color.accentColor)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

private struct QuirkySuggestion: View {
    let title: String; let symbol: String; let prompt: String; let action: (String?) -> Void
    var body: some View {
        Button { action(prompt) } label: {
            HStack(spacing: 10) { Image(systemName: symbol).frame(width: 18).foregroundStyle(Color.accentColor); Text(title); Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary) }
                .padding(.horizontal, 13).padding(.vertical, 10).contentShape(.rect)
        }.buttonStyle(.plain).background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 11))
    }
}

private struct QuirkyMessageRow: View {
    let message: QuirkyChatMessage
    var body: some View {
        if message.role == .user {
            HStack { Spacer(minLength: 50); Text(message.text).textSelection(.enabled).padding(.horizontal, 13).padding(.vertical, 9).background(Color.accentColor, in: .rect(cornerRadius: 14)).foregroundStyle(.white) }
        } else {
            HStack(alignment: .top, spacing: 10) {
                QuirkyMark(size: 30)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) { Text("Quirky").font(.caption.bold()); if let model = message.model { Text(model.title).font(.caption2).foregroundStyle(.tertiary) } }
                    Text(renderedText).textSelection(.enabled).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 24)
            }
        }
    }
    private var renderedText: AttributedString { (try? AttributedString(markdown: message.text)) ?? AttributedString(message.text) }
}

private struct PasteTranscriptSheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let podcast: Podcast
    @State private var text = ""
    var body: some View {
        NavigationStack {
            TextEditor(text: $text).font(.body.monospaced()).padding()
                .navigationTitle("Paste Transcript")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Summarize") {
                            let document = TranscriptImporter.document(text: text, podcastID: podcast.id)
                            viewModel.generateSummary(for: podcast, transcript: document); dismiss()
                        }.buttonStyle(.glassProminent).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }.frame(width: 680, height: 520)
    }
}

private extension Double {
    var formattedTimestamp: String {
        let total = Int(self), hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }
}
