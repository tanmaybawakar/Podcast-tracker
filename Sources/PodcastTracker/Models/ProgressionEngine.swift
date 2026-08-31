import Foundation

enum ProgressionEngine {
    static func awardNewTrackedMinutes(activity: inout DailyLearningActivity) -> Int {
        let completedMinutes = Int(activity.watchedSeconds / 60)
        guard completedMinutes > activity.xpAwardedMinutes else { return 0 }
        let reward = completedMinutes - activity.xpAwardedMinutes
        activity.xpAwardedMinutes = completedMinutes
        activity.xpEarned += reward
        return reward
    }

    static func migrateAchievements(_ saved: [Achievement]) -> [Achievement] {
        let savedByID = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
        return Achievement.allAchievements.map { definition in
            guard let old = savedByID[definition.id] else { return definition }
            var value = definition
            value.isUnlocked = old.isUnlocked
            value.unlockedDate = old.unlockedDate
            return value
        }
    }
}
