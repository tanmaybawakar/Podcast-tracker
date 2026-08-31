import SwiftUI

struct LearningProgressView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var displayedMonth = Date()
    @State private var showScheduleSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Learning, measured honestly").font(.largeTitle.bold())
                        Text("Minutes first. XP and levels are supporting signals.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    LevelSummary()
                }
                calendar
                goals
                ReplacementReview()
                AchievementsView()
            }.padding(28).frame(maxWidth: 1080, alignment: .leading)
        }
        .sheet(isPresented: $showScheduleSheet) {
            ScheduleDaySheet(day: viewModel.selectedCalendarDate).environmentObject(viewModel)
        }
    }

    private var calendar: some View {
        VStack(spacing: 16) {
            HStack {
                Text(displayedMonth.formatted(.dateTime.month(.wide).year())).font(.title2.bold())
                Spacer()
                Button("Previous Month", systemImage: "chevron.left") { shiftMonth(-1) }.labelStyle(.iconOnly)
                Button("Today") { displayedMonth = Date(); viewModel.selectedCalendarDate = Date() }
                Button("Next Month", systemImage: "chevron.right") { shiftMonth(1) }.labelStyle(.iconOnly)
            }
            MonthGrid(
                month: displayedMonth,
                selection: $viewModel.selectedCalendarDate,
                activities: viewModel.activities,
                scheduledDates: viewModel.podcasts.compactMap(\.scheduledAt)
            )
            if let day = viewModel.activity(for: viewModel.selectedCalendarDate) {
                HStack(spacing: 24) {
                    Label("\(Int(day.watchedSeconds / 60)) minutes", systemImage: "timer")
                    Label("\(day.sessions) sessions", systemImage: "play.circle")
                    Label("\(day.xpEarned) XP", systemImage: "sparkles")
                    Label("\(day.completedPodcastIDs.count) completed", systemImage: "checkmark.circle")
                }.font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No recorded activity on this day.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Text("Scheduled").font(.headline)
                Spacer()
                Button("Add Podcast", systemImage: "calendar.badge.plus") { showScheduleSheet = true }
                    .buttonStyle(.glass)
            }
            let scheduled = viewModel.scheduledPodcasts(on: viewModel.selectedCalendarDate)
            if scheduled.isEmpty {
                Text("Nothing scheduled for this day.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(scheduled) { podcast in
                    HStack {
                        Image(systemName: "play.rectangle")
                        VStack(alignment: .leading) {
                            Text(podcast.title).lineLimit(1)
                            if let date = podcast.scheduledAt {
                                Text(date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Open") { viewModel.selectPodcast(podcast) }.buttonStyle(.glass)
                        Button("Remove Schedule", systemImage: "xmark") { viewModel.removeSchedule(for: podcast) }
                            .labelStyle(.iconOnly).buttonStyle(.glass)
                    }
                }
            }
        }.padding(20).background(.quaternary.opacity(0.28), in: .rect(cornerRadius: 18))
    }

    private var goals: some View {
        HStack(spacing: 16) {
            GoalCard(title: "Daily", value: viewModel.todayActivity?.watchedSeconds ?? 0, target: viewModel.habitSettings.currentDailyGoalMinutes * 60, label: "\(viewModel.todayWatchedMinutes) / \(Int(viewModel.habitSettings.currentDailyGoalMinutes)) min")
            GoalCard(title: "Weekly", value: viewModel.stats.weeklySecondsWatched, target: viewModel.stats.weeklyGoalHours * 3600, label: "\(viewModel.stats.formattedWeeklyTime) / \(viewModel.stats.weeklyGoalHours.formatted())h")
        }
    }

    private func shiftMonth(_ value: Int) { displayedMonth = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) ?? displayedMonth }
}

private struct ReplacementReview: View {
    @EnvironmentObject private var viewModel: AppViewModel

    private var insights: RescueInsights { viewModel.weeklyRescueInsights }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Distraction replacement", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.title2.bold())
                    Text("A private, local view of whether Rescue is changing the behavior that matters.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Rescue Me", systemImage: "bolt.fill") { viewModel.showRescueSheet = true }
                    .buttonStyle(.glassProminent)
                    .disabled(viewModel.nextPodcast == nil)
            }

            HStack(spacing: 0) {
                insightMetric("Rescues completed", value: "\(insights.completed)")
                Divider().frame(height: 38).padding(.horizontal, 20)
                insightMetric("Minutes reclaimed", value: "\(insights.reclaimedMinutes)")
                Divider().frame(height: 38).padding(.horizontal, 20)
                insightMetric("Promises kept", value: completionLabel)
                Spacer()
            }

            if let cue = insights.leadingCue {
                Label("Biggest pull this week: \(cue.title)", systemImage: cue.symbolName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(insights.coachingMessage)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(20)
        .background(.quaternary.opacity(0.28), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    private var completionLabel: String {
        guard let rate = insights.completionRate else { return "—" }
        return rate.formatted(.percent.precision(.fractionLength(0)))
    }

    private func insightMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct LevelSummary: View {
    @EnvironmentObject private var viewModel: AppViewModel
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: viewModel.stats.currentLevel.iconName).font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading) {
                Text("Level \(viewModel.stats.currentLevel.number) · \(viewModel.stats.currentLevel.title)").font(.headline)
                ProgressView(value: viewModel.stats.levelProgress).frame(width: 180)
                Text("\(viewModel.stats.totalXP) total XP").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(14).glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

private struct GoalCard: View {
    let title: String; let value: Double; let target: Double; let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ProgressView(value: min(value / max(target, 1), 1))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.quaternary.opacity(0.28), in: .rect(cornerRadius: 16))
    }
}

private struct MonthGrid: View {
    let month: Date
    @Binding var selection: Date
    let activities: [DailyLearningActivity]
    let scheduledDates: [Date]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private var days: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let blanks = Array<Date?>(repeating: nil, count: weekday - 1)
        return blanks + range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }.map(Optional.some)
    }
    var body: some View {
        VStack(spacing: 7) {
            LazyVGrid(columns: columns) {
                ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date { dayButton(date) } else { Color.clear.frame(height: 42) }
                }
            }
        }
    }
    private func dayButton(_ date: Date) -> some View {
        let key = LearningCalendar.dateKey(for: date)
        let activity = activities.first { $0.dateKey == key }
        let isScheduled = scheduledDates.contains { Calendar.current.isDate($0, inSameDayAs: date) }
        let selected = Calendar.current.isDate(date, inSameDayAs: selection)
        return Group {
            if selected { dayButtonLabel(date, activity: activity, isScheduled: isScheduled).buttonStyle(.glassProminent) }
            else { dayButtonLabel(date, activity: activity, isScheduled: isScheduled).buttonStyle(.plain) }
        }.accessibilityLabel(date.formatted(date: .complete, time: .omitted))
    }

    private func dayButtonLabel(_ date: Date, activity: DailyLearningActivity?, isScheduled: Bool) -> some View {
        Button { selection = date } label: {
            VStack(spacing: 3) {
                Text("\(Calendar.current.component(.day, from: date))").monospacedDigit()
                HStack(spacing: 3) {
                    Circle().fill(activity?.goalCompleted == true ? Color.green : activity == nil ? Color.clear : Color.accentColor).frame(width: 5, height: 5)
                    Circle().fill(isScheduled ? Color.orange : Color.clear).frame(width: 5, height: 5)
                }
            }.frame(maxWidth: .infinity, minHeight: 38)
        }
    }
}
