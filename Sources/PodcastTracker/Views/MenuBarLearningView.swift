import AppKit
import SwiftUI

enum MenuBarText {
    static func shortened(_ value: String, limit: Int = 30) -> String {
        guard value.count > limit, limit > 3 else { return String(value.prefix(max(0, limit))) }
        return String(value.prefix(limit - 3)) + "..."
    }
}

struct MenuBarLearningView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        if viewModel.isTracking {
            Label("Learning · \(viewModel.currentSessionSeconds.formattedTime)", systemImage: "waveform")
        } else if let commitment = viewModel.latestActiveCommitment {
            Label("Promise · \(Int(ceil(commitment.remainingSeconds / 60))) min left", systemImage: "timer")
        } else {
            Label("Today · \(viewModel.todayRemainingMinutes) min left", systemImage: "target")
        }

        Divider()

        if let podcast = viewModel.committedPodcast ?? viewModel.selectedPodcast ?? viewModel.nextPodcast {
            Button {
                viewModel.selectPodcast(podcast)
                revealMainWindow()
            } label: {
                Label(MenuBarText.shortened("Continue \(podcast.title)"), systemImage: "play.fill")
            }

            Menu("Rescue from…", systemImage: "bolt.fill") {
                ForEach(DistractionCue.rescueChoices) { cue in
                    Button {
                        viewModel.prepareRescue(cue: cue, minutes: 5)
                        revealMainWindow()
                    } label: {
                        Label(cue.title, systemImage: cue.symbolName)
                    }
                }
            }
        } else {
            Button("Add Your First Episode…", systemImage: "plus") {
                viewModel.showAddPodcast = true
                revealMainWindow()
            }
        }

        Button("Open PodTrackio", systemImage: "macwindow") { revealMainWindow() }

        Divider()

        SettingsLink { Label("Settings…", systemImage: "gearshape") }
        Button("Quit PodTrackio") { NSApplication.shared.terminate(nil) }
    }

    private func revealMainWindow() {
        (NSApp.delegate as? AppDelegate)?.showPrimaryWindow()
    }
}
