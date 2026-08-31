import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                rescueCard
                if let next = viewModel.nextPodcast { nextEpisode(next) }
                else { ContentUnavailableView("Build your learning queue", systemImage: "books.vertical", description: Text("Add an educational episode to begin.")) }
                LazyVGrid(columns: columns, spacing: 16) {
                    metric("Today", value: "\(viewModel.todayWatchedMinutes) min", detail: "\(viewModel.todayRemainingMinutes) remaining", symbol: "timer")
                    metric("Streak", value: "\(viewModel.stats.currentStreak) days", detail: "5 minutes keeps it alive", symbol: "flame")
                    metric("Build-Up", value: "\(Int(viewModel.habitSettings.currentDailyGoalMinutes)) min/day", detail: viewModel.habitSettings.adaptiveBuildUpEnabled ? "Adapts each week" : "Fixed target", symbol: "chart.line.uptrend.xyaxis")
                }
                recentActivity
            }
            .padding(28)
            .frame(maxWidth: 1080, alignment: .leading)
        }
        .background(.background)
    }

    private var rescueCard: some View {
        let insights = viewModel.weeklyRescueInsights
        return HStack(spacing: 18) {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("About to waste time?").font(.headline)
                Text("Name the impulse. Replace it with one small learning win.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if insights.attempts > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(insights.completed) kept · \(insights.reclaimedMinutes) min")
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.numericText())
                    Text("replaced this week")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button("Rescue Me", systemImage: "bolt.fill") { viewModel.showRescueSheet = true }
                .buttonStyle(.glassProminent)
                .disabled(viewModel.nextPodcast == nil)
        }
        .padding(18)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.subheadline).foregroundStyle(.secondary)
            Text(viewModel.todayRemainingMinutes == 0 ? "Today’s learning is complete." : "Make the next \(viewModel.todayRemainingMinutes) minutes count.")
                .font(.largeTitle.bold()).textSelection(.enabled)
        }
    }

    private func nextEpisode(_ podcast: Podcast) -> some View {
        HStack(spacing: 22) {
            AsyncImage(url: podcast.thumbnailURL.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() }
                placeholder: { Rectangle().fill(.quaternary).overlay { Image(systemName: "play.rectangle") } }
                .frame(width: 220, height: 124).clipShape(.rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 10) {
                Text("UP NEXT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(podcast.title).font(.title2.weight(.semibold)).lineLimit(2)
                ProgressView(value: podcast.progressPercentage)
                GlassEffectContainer(spacing: 10) {
                    HStack {
                        Button("Resume", systemImage: "play.fill") { viewModel.selectPodcast(podcast) }
                            .buttonStyle(.glassProminent)
                        Button("Start 5 Minutes", systemImage: "timer") {
                            viewModel.prepareCommitment(
                                for: podcast,
                                minutes: 5,
                                cue: .today,
                                launchIntent: .explicitUserAction
                            )
                        }.buttonStyle(.glass)
                    }
                }
            }
            Spacer()
        }
        .padding(20)
        .background(.background.secondary, in: .rect(cornerRadius: 18))
    }

    private func metric(_ title: String, value: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).contentTransition(.numericText())
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent activity").font(.title2.bold())
            if viewModel.activities.isEmpty { Text("Your accurate daily history begins here.").foregroundStyle(.secondary) }
            ForEach(viewModel.activities.sorted { $0.dateKey > $1.dateKey }.prefix(5)) { day in
                HStack {
                    Image(systemName: day.goalCompleted ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(day.goalCompleted ? .green : .secondary)
                    Text(LearningCalendar.date(from: day.dateKey)?.formatted(date: .abbreviated, time: .omitted) ?? day.dateKey)
                    Spacer()
                    Text("\(Int(day.watchedSeconds / 60)) min · \(day.xpEarned) XP").foregroundStyle(.secondary)
                }.padding(.vertical, 5)
            }
        }
    }
}

struct DistractionRescueSheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var cue: DistractionCue = .scrolling
    @State private var minutes = 5

    var body: some View {
        NavigationStack {
            Form {
                Section("What is pulling you away?") {
                    Picker("Distraction", selection: $cue) {
                        ForEach(DistractionCue.rescueChoices) { item in
                            Label(item.title, systemImage: item.symbolName).tag(item)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .accessibilityHint("This only personalizes your rescue history and reminders")
                }

                Section("Make the smallest promise you will keep") {
                    Picker("Learning block", selection: $minutes) {
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("20 min").tag(20)
                    }
                    .pickerStyle(.segmented)
                }

                if let podcast = viewModel.nextPodcast {
                    Section("Ready next") {
                        LabeledContent("Episode", value: podcast.title)
                        if podcast.hasProgress {
                            LabeledContent("Resume from", value: podcast.lastPlaybackPosition.formattedTime)
                        }
                    }
                }

                Text("The timer begins only when the video is actually playing. Pausing keeps your progress; it never fakes watch time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .navigationTitle("Distraction Rescue")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Replace It with \(minutes) Minutes", systemImage: "play.fill") {
                        viewModel.prepareRescue(cue: cue, minutes: minutes)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(viewModel.nextPodcast == nil)
                }
            }
        }
        .frame(width: 560, height: 560)
    }
}
