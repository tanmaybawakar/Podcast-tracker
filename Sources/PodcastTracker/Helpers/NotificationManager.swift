import Foundation
import UserNotifications

enum LearningNotificationStage: String, Codable, CaseIterable, Sendable {
    case morning
    case afternoon
    case evening
    case rescue
    case snooze
}

struct LearningNotificationPlanItem: Identifiable, Equatable, Sendable {
    var id: String
    var fireDate: Date
    var stage: LearningNotificationStage
    var title: String
    var body: String
    var podcastID: UUID
}

enum NotificationPlanner {
    static func plan(
        now: Date,
        preferences: NotificationPreferences,
        activities: [DailyLearningActivity],
        currentGoalMinutes: Double,
        nextPodcast: Podcast?,
        isPlaying: Bool,
        distractionCue: DistractionCue? = nil,
        distractionPattern: DistractionPattern? = nil,
        calendar: Calendar = .current
    ) -> [LearningNotificationPlanItem] {
        guard preferences.isEnabled, !isPlaying, let nextPodcast else { return [] }
        var result: [LearningNotificationPlanItem] = []

        for dayOffset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            guard preferences.enabledWeekdays.contains(weekday) else { continue }
            let key = LearningCalendar.dateKey(for: day, calendar: calendar)
            let activity = activities.first { $0.dateKey == key }
            guard activity?.goalCompleted != true else { continue }
            let watchedMinutes = (activity?.watchedSeconds ?? 0) / 60
            let remaining = max(0, Int(ceil(currentGoalMinutes - watchedMinutes)))

            for (stage, time) in [
                (LearningNotificationStage.morning, preferences.morning),
                (.afternoon, preferences.afternoon),
                (.evening, preferences.evening)
            ] {
                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = time.hour
                components.minute = time.minute
                guard let fireDate = calendar.date(from: components), fireDate > now,
                      !isQuiet(fireDate, preferences: preferences, calendar: calendar) else { continue }

                let copy: (String, String)
                switch stage {
                case .morning:
                    copy = ("Your next lesson is ready", "Continue \(nextPodcast.title). Today’s target is \(Int(currentGoalMinutes)) minutes.")
                case .afternoon:
                    copy = (
                        distractionCue.map(momentumTitle(for:)) ?? "Keep the learning loop alive",
                        "You have \(remaining) minutes left today. Trade the next five for \(nextPodcast.title)."
                    )
                case .evening:
                    let yesterdayKey = calendar.date(byAdding: .day, value: -1, to: day).map { LearningCalendar.dateKey(for: $0, calendar: calendar) }
                    let missedYesterday = yesterdayKey.map { key in
                        activities.first(where: { $0.dateKey == key })?.goalCompleted != true
                    } ?? false
                    copy = ("\(remaining) minutes to protect today", missedYesterday
                            ? "Don’t miss twice. \(distractionCue.map(rescueLead(for:)) ?? "Choose the useful five minutes.") Resume \(nextPodcast.title)."
                            : distractionCue.map { "\(rescueLead(for: $0)) A short finish keeps your learning streak intact." }
                                ?? "A short finish keeps your learning streak intact.")
                case .rescue, .snooze:
                    continue
                }
                result.append(.init(
                    id: "learning.\(key).\(stage.rawValue)", fireDate: fireDate,
                    stage: stage, title: copy.0, body: copy.1, podcastID: nextPodcast.id
                ))
            }
        }

        if let pattern = distractionPattern,
           preferences.enabledWeekdays.contains(pattern.weekday),
           let fireDate = pattern.nextFireDate(after: now, calendar: calendar),
           !isQuiet(fireDate, preferences: preferences, calendar: calendar) {
            let key = LearningCalendar.dateKey(for: fireDate, calendar: calendar)
            let goalIsComplete = activities.first(where: { $0.dateKey == key })?.goalCompleted == true
            if !goalIsComplete {
                let adaptive = LearningNotificationPlanItem(
                    id: "learning.\(key).rescue",
                    fireDate: fireDate,
                    stage: .rescue,
                    title: "Before \(pattern.cue.title.lowercased()) takes the slot",
                    body: "This is a usual distraction window. Open \(nextPodcast.title) and take the first five minutes back.",
                    podcastID: nextPodcast.id
                )
                if let nearbyIndex = result.indices
                    .filter({ calendar.isDate(result[$0].fireDate, inSameDayAs: fireDate) })
                    .min(by: {
                        abs(result[$0].fireDate.timeIntervalSince(fireDate)) < abs(result[$1].fireDate.timeIntervalSince(fireDate))
                    }),
                   abs(result[nearbyIndex].fireDate.timeIntervalSince(fireDate)) <= 90 * 60 {
                    result.remove(at: nearbyIndex)
                }
                result.append(adaptive)
            }
        }
        return result
    }

    private static func momentumTitle(for cue: DistractionCue) -> String {
        switch cue {
        case .scrolling: "Before the scroll takes over"
        case .streaming: "Before another show starts"
        case .anime: "Before the next anime episode"
        case .gaming: "Before you queue another game"
        case .other, .notification, .today, .momentum: "Choose the useful five minutes"
        }
    }

    private static func rescueLead(for cue: DistractionCue) -> String {
        switch cue {
        case .scrolling: "Trade five minutes of scrolling for learning."
        case .streaming: "Trade five minutes of streaming for learning."
        case .anime: "Trade five minutes of anime for learning."
        case .gaming: "Trade five minutes of gaming for learning."
        case .other, .notification, .today, .momentum: "Choose the useful five minutes."
        }
    }

    private static func isQuiet(_ date: Date, preferences: NotificationPreferences, calendar: Calendar) -> Bool {
        guard preferences.quietHoursEnabled else { return false }
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let start = preferences.quietHoursStart.hour * 60 + preferences.quietHoursStart.minute
        let end = preferences.quietHoursEnd.hour * 60 + preferences.quietHoursEnd.minute
        return start <= end ? (start..<end).contains(minutes) : minutes >= start || minutes < end
    }
}

extension Notification.Name {
    static let openPodcastFromNotification = Notification.Name("openPodcastFromNotification")
    static let startFiveMinutesFromNotification = Notification.Name("startFiveMinutesFromNotification")
}

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    nonisolated static let categoryIdentifier = "LEARNING_REMINDER"
    nonisolated static let resumeAction = "RESUME_EPISODE"
    nonisolated static let fiveMinuteAction = "START_FIVE_MINUTES"
    nonisolated static let snoozeAction = "SNOOZE_30"

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private let center = UNUserNotificationCenter.current()

    private override init() { super.init() }

    func registerBeforeLaunchCompletes() {
        center.delegate = self
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [
                UNNotificationAction(identifier: Self.resumeAction, title: "Resume", options: [.foreground]),
                UNNotificationAction(identifier: Self.fiveMinuteAction, title: "Start 5 Minutes", options: [.foreground]),
                UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze 30 Minutes")
            ],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
        refreshAuthorizationStatus()
    }

    func requestAuthorization() async -> Bool {
        do {
            let allowed = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            refreshAuthorizationStatus()
            return allowed
        } catch {
            refreshAuthorizationStatus()
            return false
        }
    }

    func replaceLearningReminders(with plan: [LearningNotificationPlanItem]) async {
        let pending = await center.pendingNotificationRequests()
        let oldIDs = pending.map(\.identifier).filter { $0.hasPrefix("learning.") }
        center.removePendingNotificationRequests(withIdentifiers: oldIDs)

        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.categoryIdentifier = Self.categoryIdentifier
            content.userInfo = ["podcastID": item.podcastID.uuidString]
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }

    func cancelToday() async {
        let prefix = "learning.\(LearningCalendar.dateKey(for: Date()))."
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
    }

    private func refreshAuthorizationStatus() {
        center.getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            Task { @MainActor [weak self, status] in self?.authorizationStatus = status }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let receivedContent = response.notification.request.content
        let podcastID = (receivedContent.userInfo["podcastID"] as? String).flatMap(UUID.init(uuidString:))
        let actionIdentifier = response.actionIdentifier
        let title = receivedContent.title
        let body = receivedContent.body
        if let podcastID {
            if actionIdentifier == Self.snoozeAction {
                Task {
                    let content = UNMutableNotificationContent()
                    content.title = title
                    content.body = body
                    content.sound = .default
                    content.categoryIdentifier = Self.categoryIdentifier
                    content.userInfo = ["podcastID": podcastID.uuidString]
                let request = UNNotificationRequest(
                    identifier: "learning.snooze.\(UUID().uuidString)", content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 30 * 60, repeats: false)
                )
                try? await UNUserNotificationCenter.current().add(request)
                }
            } else {
                let name: Notification.Name = actionIdentifier == Self.fiveMinuteAction ? .startFiveMinutesFromNotification : .openPodcastFromNotification
                NotificationCenter.default.post(name: name, object: podcastID)
            }
        }
        completionHandler()
    }
}
