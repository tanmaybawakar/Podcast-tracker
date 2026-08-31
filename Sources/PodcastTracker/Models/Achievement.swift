import Foundation

/// Represents a gamification achievement/badge
struct Achievement: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let iconName: String
    let xpReward: Int
    let category: AchievementCategory
    var isUnlocked: Bool = false
    var unlockedDate: Date? = nil

    var categoryIcon: String {
        switch category {
        case .listening: return "headphones"
        case .streak: return "flame.fill"
        case .notes: return "square.and.pencil"
        case .explorer: return "safari.fill"
        case .mastery: return "rosette"
        case .social: return "person.2.fill"
        case .milestone: return "trophy.fill"
        }
    }
}

enum AchievementCategory: String, Codable, CaseIterable {
    case listening = "Listening"
    case streak = "Streak"
    case notes = "Notes"
    case explorer = "Explorer"
    case mastery = "Mastery"
    case social = "Social"
    case milestone = "Milestone"

    var displayColor: String {
        switch self {
        case .listening: return "cyan"
        case .streak: return "orange"
        case .notes: return "green"
        case .explorer: return "purple"
        case .mastery: return "gold"
        case .social: return "pink"
        case .milestone: return "red"
        }
    }
}

// MARK: - Default Achievements

extension Achievement {
    static let allAchievements: [Achievement] = [
        // Listening achievements
        Achievement(id: "first_listen", title: "First Steps", description: "Watch your first podcast", iconName: "play.circle.fill", xpReward: 10, category: .listening),
        Achievement(id: "one_hour", title: "Hour Power", description: "Watch 1 hour of podcasts", iconName: "clock.fill", xpReward: 25, category: .listening),
        Achievement(id: "five_hours", title: "Deep Diver", description: "Watch 5 hours of podcasts", iconName: "waveform", xpReward: 50, category: .listening),
        Achievement(id: "ten_hours", title: "Knowledge Seeker", description: "Watch 10 hours of podcasts", iconName: "lightbulb.fill", xpReward: 100, category: .listening),
        Achievement(id: "twentyfive_hours", title: "Marathon Listener", description: "Watch 25 hours of podcasts", iconName: "flame.fill", xpReward: 200, category: .listening),
        Achievement(id: "fifty_hours", title: "Podcast Warrior", description: "Watch 50 hours of podcasts", iconName: "shield.fill", xpReward: 500, category: .listening),
        Achievement(id: "hundred_hours", title: "Century Club", description: "Watch 100 hours of podcasts", iconName: "star.circle.fill", xpReward: 1000, category: .listening),

        // Streak achievements
        Achievement(id: "streak_3", title: "Getting Started", description: "Maintain a 3-day streak", iconName: "flame", xpReward: 30, category: .streak),
        Achievement(id: "streak_7", title: "Week Warrior", description: "Maintain a 7-day streak", iconName: "flame.fill", xpReward: 75, category: .streak),
        Achievement(id: "streak_14", title: "Fortnight Focus", description: "Maintain a 14-day streak", iconName: "bolt.fill", xpReward: 150, category: .streak),
        Achievement(id: "streak_30", title: "Monthly Master", description: "Maintain a 30-day streak", iconName: "crown.fill", xpReward: 300, category: .streak),
        Achievement(id: "streak_100", title: "Unstoppable", description: "Maintain a 100-day streak", iconName: "trophy.fill", xpReward: 1000, category: .streak),

        // Notes achievements
        Achievement(id: "first_note", title: "Scribbler", description: "Write your first note", iconName: "pencil", xpReward: 10, category: .notes),
        Achievement(id: "ten_notes", title: "Note Taker", description: "Write notes for 10 podcasts", iconName: "doc.text.fill", xpReward: 50, category: .notes),
        Achievement(id: "twentyfive_notes", title: "Studious Scholar", description: "Write notes for 25 podcasts", iconName: "book.fill", xpReward: 150, category: .notes),

        // Explorer achievements
        Achievement(id: "five_podcasts", title: "Explorer", description: "Add 5 podcasts to your library", iconName: "safari.fill", xpReward: 25, category: .explorer),
        Achievement(id: "ten_podcasts", title: "Curator", description: "Add 10 podcasts to your library", iconName: "square.grid.3x3.fill", xpReward: 50, category: .explorer),
        Achievement(id: "twentyfive_podcasts", title: "Collector", description: "Add 25 podcasts to your library", iconName: "rectangle.stack.fill", xpReward: 100, category: .explorer),
        Achievement(id: "three_categories", title: "Diverse Thinker", description: "Watch podcasts in 3 different categories", iconName: "paintpalette.fill", xpReward: 50, category: .explorer),
        Achievement(id: "six_categories", title: "Renaissance Mind", description: "Learn across 6 different categories", iconName: "globe", xpReward: 150, category: .explorer),

        // Mastery achievements
        Achievement(id: "complete_first", title: "Completionist", description: "Finish watching a podcast", iconName: "checkmark.circle.fill", xpReward: 20, category: .mastery),
        Achievement(id: "complete_five", title: "Achiever", description: "Finish watching 5 podcasts", iconName: "medal.fill", xpReward: 100, category: .mastery),
        Achievement(id: "complete_ten", title: "Dedicated Learner", description: "Finish watching 10 podcasts", iconName: "star.fill", xpReward: 200, category: .mastery),
        Achievement(id: "weekly_goal", title: "Goal Crusher", description: "Complete your weekly goal", iconName: "target", xpReward: 75, category: .mastery),
        Achievement(id: "daily_goal_7", title: "Consistency King", description: "Hit your daily goal 7 days in a row", iconName: "repeat.circle.fill", xpReward: 200, category: .mastery),
        Achievement(id: "first_summary", title: "Distilled", description: "Generate your first learning summary", iconName: "text.alignleft", xpReward: 0, category: .mastery),
        Achievement(id: "first_action_plan", title: "Applied Learning", description: "Complete an episode action plan", iconName: "checklist.checked", xpReward: 0, category: .mastery),

        // Milestone achievements
        Achievement(id: "level_5", title: "Rising Star", description: "Reach Level 5", iconName: "sparkles", xpReward: 100, category: .milestone),
        Achievement(id: "level_10", title: "Transcendence", description: "Reach Level 10", iconName: "sun.max.fill", xpReward: 500, category: .milestone),
    ]
}
