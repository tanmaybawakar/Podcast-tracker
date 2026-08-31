import Foundation

/// Tracks user's overall progress, goals, streaks, and XP
struct UserStats: Codable {
    var id: String = "default"
    var totalSecondsWatched: Double = 0
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastActiveDate: Date? = nil
    var totalXP: Int = 0
    var weeklyGoalHours: Double = 5.0
    var dailyGoalMinutes: Double = 30.0
    var weeklySecondsWatched: Double = 0
    var dailySecondsWatched: Double = 0
    var weekStartDate: Date? = nil
    var dayStartDate: Date? = nil
    var unlockedAchievementIds: [String] = []
    var podcastsCompleted: Int = 0
    var totalNotesTaken: Int = 0
    var totalPodcastsAdded: Int = 0
    var sessionsCount: Int = 0
    var longestSessionSeconds: Double = 0

    // MARK: - Computed Properties

    var totalHoursWatched: Double {
        totalSecondsWatched / 3600.0
    }

    var totalMinutesWatched: Double {
        totalSecondsWatched / 60.0
    }

    var weeklyGoalProgress: Double {
        let goal = weeklyGoalHours * 3600.0
        guard goal > 0 else { return 0 }
        return min(weeklySecondsWatched / goal, 1.0)
    }

    var dailyGoalProgress: Double {
        let goal = dailyGoalMinutes * 60.0
        guard goal > 0 else { return 0 }
        return min(dailySecondsWatched / goal, 1.0)
    }

    var formattedTotalTime: String {
        let hours = Int(totalSecondsWatched) / 3600
        let minutes = (Int(totalSecondsWatched) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    var formattedWeeklyTime: String {
        let hours = Int(weeklySecondsWatched) / 3600
        let minutes = (Int(weeklySecondsWatched) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var formattedDailyTime: String {
        let minutes = Int(dailySecondsWatched) / 60
        let seconds = Int(dailySecondsWatched) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    // MARK: - Level System

    var currentLevel: Level {
        Level.forXP(totalXP)
    }

    var xpForCurrentLevel: Int {
        totalXP - currentLevel.minXP
    }

    var xpToNextLevel: Int {
        currentLevel.xpToNext
    }

    var levelProgress: Double {
        guard xpToNextLevel > 0 else { return 1.0 }
        return Double(xpForCurrentLevel) / Double(xpToNextLevel)
    }

    // MARK: - Mutation Helpers

    mutating func resetDailyIfNeeded() {
        let calendar = Calendar.current
        if let dayStart = dayStartDate, !calendar.isDateInToday(dayStart) {
            dailySecondsWatched = 0
            dayStartDate = Date()
        } else if dayStartDate == nil {
            dayStartDate = Date()
        }
    }

    mutating func resetWeeklyIfNeeded() {
        let calendar = Calendar.current
        if let weekStart = weekStartDate {
            let weeksSince = calendar.dateComponents([.weekOfYear], from: weekStart, to: Date()).weekOfYear ?? 0
            if weeksSince >= 1 {
                weeklySecondsWatched = 0
                weekStartDate = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))
            }
        } else {
            weekStartDate = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))
        }
    }

    mutating func updateStreak() {
        let calendar = Calendar.current
        if let lastActive = lastActiveDate {
            if calendar.isDateInToday(lastActive) {
                // Already tracked today
                return
            } else if calendar.isDateInYesterday(lastActive) {
                currentStreak += 1
            } else {
                currentStreak = 1
            }
        } else {
            currentStreak = 1
        }
        longestStreak = max(longestStreak, currentStreak)
        lastActiveDate = Date()
    }
}

// MARK: - Level Definition

struct Level: Codable {
    let number: Int
    let title: String
    let minXP: Int
    let xpToNext: Int
    let iconName: String
    let tierBadge: String

    static let levels: [Level] = [
        Level(number: 1, title: "Newcomer", minXP: 0, xpToNext: 100, iconName: "sparkles", tierBadge: "Tier I"),
        Level(number: 2, title: "Listener", minXP: 100, xpToNext: 200, iconName: "headphones", tierBadge: "Tier II"),
        Level(number: 3, title: "Enthusiast", minXP: 300, xpToNext: 300, iconName: "books.vertical.fill", tierBadge: "Tier III"),
        Level(number: 4, title: "Scholar", minXP: 600, xpToNext: 400, iconName: "graduationcap.fill", tierBadge: "Tier IV"),
        Level(number: 5, title: "Expert", minXP: 1000, xpToNext: 500, iconName: "star.circle.fill", tierBadge: "Tier V"),
        Level(number: 6, title: "Guru", minXP: 1500, xpToNext: 1000, iconName: "brain.head.profile", tierBadge: "Tier VI"),
        Level(number: 7, title: "Master", minXP: 2500, xpToNext: 1500, iconName: "crown.fill", tierBadge: "Tier VII"),
        Level(number: 8, title: "Sage", minXP: 4000, xpToNext: 2000, iconName: "sparkle.magnifyingglass", tierBadge: "Tier VIII"),
        Level(number: 9, title: "Legend", minXP: 6000, xpToNext: 4000, iconName: "diamond.fill", tierBadge: "Tier IX"),
        Level(number: 10, title: "Grandmaster", minXP: 10000, xpToNext: 0, iconName: "trophy.fill", tierBadge: "Tier X"),
    ]

    static func forXP(_ xp: Int) -> Level {
        for level in levels.reversed() {
            if xp >= level.minXP {
                return level
            }
        }
        return levels[0]
    }
}
