import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PlayerView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let podcast: Podcast
    @StateObject private var playerController = PlayerController()
    @State private var useNativePlayer = true
    @State private var playbackFailed = false
    @State private var playbackAttemptID = UUID()
    @State private var nativeRetryCount = 0
    @State private var showFileImporter = false
    @State private var showPasteSheet = false

    private var currentPodcast: Podcast { viewModel.podcasts.first(where: { $0.id == podcast.id }) ?? podcast }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if playbackFailed {
                    unavailableView
                } else if useNativePlayer {
                    let attemptID = playbackAttemptID
                    NativePlayerView(
                        videoId: currentPodcast.youtubeVideoId,
                        startPosition: currentPodcast.lastPlaybackPosition,
                        reloadID: attemptID,
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
            }
            .font(.subheadline).padding(16)
        }
        .background(.black.opacity(0.92))
        .safeAreaInset(edge: .bottom, spacing: 10) {
            if let commitment = viewModel.completedCommitment, commitment.podcastID == currentPodcast.id {
                CommitmentWin(commitment: commitment).environmentObject(viewModel).padding(.horizontal, 16)
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
        .task(id: currentPodcast.id) {
            resetPlayback()
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
            useNativePlayer = false
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
                    SummarySection("60-second brief", symbol: "text.alignleft") { Text(summary.brief).font(.body).textSelection(.enabled).lineSpacing(4) }
                    SummarySection("Key topics", symbol: "timeline.selection") {
                        ForEach(Array(summary.keyTopics.enumerated()), id: \.element.id) { index, topic in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("\(index + 1)").foregroundStyle(.secondary).monospacedDigit()
                                    Text(topic.title).font(.headline)
                                    Spacer()
                                    if let seconds = topic.timestampSeconds {
                                        Button(seconds.formattedTimestamp) { playerController.seek(to: seconds) }
                                            .buttonStyle(.glass).controlSize(.small)
                                    }
                                }
                                Text(topic.explanation).foregroundStyle(.secondary).textSelection(.enabled)
                            }.padding(.vertical, 5)
                        }
                    }
                    SummarySection("Major takeaways", symbol: "lightbulb.max") {
                        ForEach(summary.majorTakeaways) { takeaway in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(takeaway.title).font(.headline)
                                Text(takeaway.explanation).foregroundStyle(.secondary).textSelection(.enabled)
                            }.padding(12).background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 10))
                        }
                    }
                    SummarySection("Action plan", symbol: "checklist") {
                        ForEach(summary.actionPlan) { action in
                            Toggle(isOn: Binding(
                                get: { viewModel.summary(for: podcast.id)?.actionPlan.first(where: { $0.id == action.id })?.isCompleted ?? false },
                                set: { _ in viewModel.toggleAction(podcastID: podcast.id, actionID: action.id) }
                            )) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(action.title).font(.headline)
                                    Text(action.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }.toggleStyle(.checkbox).padding(.vertical, 4)
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
        case .idle, .completed: "PodTrackio first looks for public captions. Your Groq key stays in Keychain."
        case .fetchingCaptions: "Looking for public captions…"
        case .needsAudioConsent: "No public captions were available. Audio transcription downloads media and consumes Groq credits."
        case .downloadingAudio(let progress): "Downloading the lowest suitable audio stream… \(Int(progress * 100))%"
        case .transcribing(let current, let total): "Transcribing audio chunk \(current) of \(total)…"
        case .synthesizing: "Crafting the brief, topic timeline, takeaways, and action plan…"
        case .needsTranscriptImport(let reason): "Automatic extraction failed: \(reason)"
        case .failed(let message): message
        }
    }

    @ViewBuilder private var progressControls: some View {
        GlassEffectContainer(spacing: 10) {
            switch viewModel.summaryState {
            case .fetchingCaptions, .downloadingAudio, .transcribing, .synthesizing:
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
