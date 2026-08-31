import Foundation

struct DailyLearningActivity: Identifiable, Codable, Hashable, Sendable {
    var dateKey: String
    var watchedSeconds: Double = 0
    var sessions: Int = 0
    var goalMinutes: Double
    var goalCompleted = false
    var xpEarned = 0
    var completedPodcastIDs: Set<UUID> = []
    var xpAwardedMinutes = 0
    var dailyGoalXPAwarded = false
    var weeklyGoalXPAwarded = false

    var id: String { dateKey }
    var qualifiesForStreak: Bool { watchedSeconds >= 300 }
}

struct HabitSettings: Codable, Equatable, Sendable {
    var adaptiveBuildUpEnabled = true
    var currentDailyGoalMinutes: Double = 15
    var startingDailyGoalMinutes: Double = 15
    var targetDailyGoalMinutes: Double = 60
    var buildUpStepMinutes: Double = 5
    var minimumQualifyingSessionMinutes: Double = 5
    var lastEvaluatedWeekKey: String?
    var lastWeeklyGoalAwardKey: String?
}

enum LearningCalendar {
    static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func weekKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", components.yearForWeekOfYear ?? 0, components.weekOfYear ?? 0)
    }

    static func evaluateBuildUp(
        settings: inout HabitSettings,
        activities: [DailyLearningActivity],
        now: Date,
        calendar: Calendar = .current
    ) {
        guard settings.adaptiveBuildUpEnabled else { return }
        let currentWeek = weekKey(for: now, calendar: calendar)
        guard settings.lastEvaluatedWeekKey != currentWeek else { return }

        defer { settings.lastEvaluatedWeekKey = currentWeek }
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let previousStart = calendar.date(byAdding: .day, value: -7, to: weekStart),
              let previousEnd = calendar.date(byAdding: .day, value: -1, to: weekStart) else { return }

        let successfulDays = activities.filter { activity in
            guard let date = date(from: activity.dateKey, calendar: calendar) else { return false }
            return date >= previousStart && date <= previousEnd && activity.goalCompleted
        }.count

        if successfulDays >= 5 {
            settings.currentDailyGoalMinutes = min(
                settings.currentDailyGoalMinutes + settings.buildUpStepMinutes,
                settings.targetDailyGoalMinutes
            )
        }
    }

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let values = key.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: values[0], month: values[1], day: values[2]))
    }
}
