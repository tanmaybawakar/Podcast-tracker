import SwiftUI

struct SchedulePodcastSheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let podcast: Podcast
    @State private var scheduledDate: Date

    init(podcast: Podcast, initialDate: Date) {
        self.podcast = podcast
        _scheduledDate = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Episode", value: podcast.title)
                DatePicker(
                    "Watch on",
                    selection: $scheduledDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                if scheduledDate <= Date() {
                    Label("Past times remain visible as missed and do not send a notification.", systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(podcast.scheduledAt == nil ? "Schedule Podcast" : "Reschedule Podcast")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if podcast.scheduledAt != nil {
                    ToolbarItem {
                        Button("Remove Schedule", role: .destructive) {
                            viewModel.removeSchedule(for: podcast)
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.schedulePodcast(podcast, at: scheduledDate)
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
        .frame(width: 520, height: 280)
    }
}

struct ScheduleDaySheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let day: Date
    @State private var podcastID: UUID?
    @State private var time: Date

    init(day: Date) {
        self.day = day
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.hour = 18
        components.minute = 0
        _time = State(initialValue: Calendar.current.date(from: components) ?? day)
    }

    private var available: [Podcast] { viewModel.podcasts.filter { !$0.isCompleted } }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Podcast", selection: $podcastID) {
                    Text("Choose an episode").tag(Optional<UUID>.none)
                    ForEach(available) { Text($0.title).tag(Optional($0.id)) }
                }
                DatePicker("Time", selection: $time, displayedComponents: [.hourAndMinute])
            }
            .formStyle(.grouped)
            .navigationTitle("Schedule for \(day.formatted(date: .abbreviated, time: .omitted))")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") {
                        guard let podcastID, let podcast = viewModel.podcasts.first(where: { $0.id == podcastID }) else { return }
                        viewModel.schedulePodcast(podcast, at: time)
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(podcastID == nil)
                }
            }
        }
        .frame(width: 520, height: 270)
    }
}
