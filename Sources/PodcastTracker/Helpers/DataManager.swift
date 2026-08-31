import Foundation

/// Manages persistence of podcasts and user stats to JSON files in Application Support
final class DataManager: @unchecked Sendable {
    static let shared = DataManager()

    private let fileManager = FileManager.default
    private let podcastsFileName = "podcasts.json"
    private let statsFileName = "user_stats.json"
    private let achievementsFileName = "achievements.json"
    private let categoriesFileName = "categories.json"
    private let activitiesFileName = "daily_learning_activity.json"
    private let summariesFileName = "podcast_summaries.json"
    private let habitsFileName = "habit_settings.json"
    private let notificationsFileName = "notification_preferences.json"
    private let commitmentsFileName = "focus_commitments.json"

    private var appSupportURL: URL {
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = urls[0].appendingPathComponent("PodcastTracker", isDirectory: true)
        if !fileManager.fileExists(atPath: appSupport.path) {
            try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        return appSupport
    }

    private var podcastsURL: URL {
        appSupportURL.appendingPathComponent(podcastsFileName)
    }

    private var statsURL: URL {
        appSupportURL.appendingPathComponent(statsFileName)
    }

    private var achievementsURL: URL {
        appSupportURL.appendingPathComponent(achievementsFileName)
    }

    private var categoriesURL: URL { appSupportURL.appendingPathComponent(categoriesFileName) }
    private var activitiesURL: URL { appSupportURL.appendingPathComponent(activitiesFileName) }
    private var summariesURL: URL { appSupportURL.appendingPathComponent(summariesFileName) }
    private var habitsURL: URL { appSupportURL.appendingPathComponent(habitsFileName) }
    private var notificationsURL: URL { appSupportURL.appendingPathComponent(notificationsFileName) }
    private var commitmentsURL: URL { appSupportURL.appendingPathComponent(commitmentsFileName) }
    var transcriptCacheURL: URL {
        let url = appSupportURL.appendingPathComponent("Transcripts", isDirectory: true)
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Podcasts

    func savePodcasts(_ podcasts: [Podcast]) {
        do {
            let data = try encoder.encode(podcasts)
            try data.write(to: podcastsURL, options: .atomic)
        } catch {
            print("❌ Failed to save podcasts: \(error)")
        }
    }

    func loadPodcasts() -> [Podcast] {
        guard fileManager.fileExists(atPath: podcastsURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: podcastsURL)
            return try decoder.decode([Podcast].self, from: data)
        } catch {
            print("❌ Failed to load podcasts: \(error)")
            return []
        }
    }

    // MARK: - User Stats

    func saveStats(_ stats: UserStats) {
        do {
            let data = try encoder.encode(stats)
            try data.write(to: statsURL, options: .atomic)
        } catch {
            print("❌ Failed to save stats: \(error)")
        }
    }

    func loadStats() -> UserStats {
        guard fileManager.fileExists(atPath: statsURL.path) else { return UserStats() }
        do {
            let data = try Data(contentsOf: statsURL)
            return try decoder.decode(UserStats.self, from: data)
        } catch {
            print("❌ Failed to load stats: \(error)")
            return UserStats()
        }
    }

    // MARK: - Achievements

    func saveAchievements(_ achievements: [Achievement]) {
        do {
            let data = try encoder.encode(achievements)
            try data.write(to: achievementsURL, options: .atomic)
        } catch {
            print("❌ Failed to save achievements: \(error)")
        }
    }

    func loadAchievements() -> [Achievement] {
        guard fileManager.fileExists(atPath: achievementsURL.path) else {
            return Achievement.allAchievements
        }
        do {
            let data = try Data(contentsOf: achievementsURL)
            var saved = try decoder.decode([Achievement].self, from: data)
            // Merge with any new achievements added in updates
            let savedIds = Set(saved.map { $0.id })
            for achievement in Achievement.allAchievements {
                if !savedIds.contains(achievement.id) {
                    saved.append(achievement)
                }
            }
            return saved
        } catch {
            print("❌ Failed to load achievements: \(error)")
            return Achievement.allAchievements
        }
    }

    // MARK: - Learning Workspace

    func saveCategories(_ categories: [LearningCategory]) { save(categories, to: categoriesURL) }

    func loadCategories() -> [LearningCategory] {
        let stored: [LearningCategory] = load([LearningCategory].self, from: categoriesURL) ?? []
        guard !stored.isEmpty else { return LearningCategory.defaults }
        let storedIDs = Set(stored.map(\.id))
        let missingDefaults = LearningCategory.defaults.filter { !storedIDs.contains($0.id) }
        return (stored + missingDefaults).sorted { $0.sortOrder < $1.sortOrder }
    }

    func saveActivities(_ activities: [DailyLearningActivity]) { save(activities, to: activitiesURL) }
    func loadActivities() -> [DailyLearningActivity] { load([DailyLearningActivity].self, from: activitiesURL) ?? [] }

    func saveSummaries(_ summaries: [PodcastSummary]) { save(summaries, to: summariesURL) }
    func loadSummaries() -> [PodcastSummary] { load([PodcastSummary].self, from: summariesURL) ?? [] }

    func saveHabitSettings(_ settings: HabitSettings) { save(settings, to: habitsURL) }
    func loadHabitSettings() -> HabitSettings { load(HabitSettings.self, from: habitsURL) ?? HabitSettings() }

    func saveNotificationPreferences(_ preferences: NotificationPreferences) { save(preferences, to: notificationsURL) }
    func loadNotificationPreferences() -> NotificationPreferences {
        load(NotificationPreferences.self, from: notificationsURL) ?? NotificationPreferences()
    }

    func saveFocusCommitments(_ commitments: [FocusCommitment]) { save(commitments, to: commitmentsURL) }
    func loadFocusCommitments() -> [FocusCommitment] { load([FocusCommitment].self, from: commitmentsURL) ?? [] }

    func saveTranscript(_ transcript: TranscriptDocument) {
        save(transcript, to: transcriptCacheURL.appendingPathComponent("\(transcript.podcastID.uuidString).json"))
    }

    func loadTranscript(for podcastID: UUID) -> TranscriptDocument? {
        load(TranscriptDocument.self, from: transcriptCacheURL.appendingPathComponent("\(podcastID.uuidString).json"))
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            print("Failed to save \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            return try decoder.decode(type, from: Data(contentsOf: url))
        } catch {
            print("Failed to load \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Reset

    func resetAllData() {
        try? fileManager.removeItem(at: podcastsURL)
        try? fileManager.removeItem(at: statsURL)
        try? fileManager.removeItem(at: achievementsURL)
        try? fileManager.removeItem(at: categoriesURL)
        try? fileManager.removeItem(at: activitiesURL)
        try? fileManager.removeItem(at: summariesURL)
        try? fileManager.removeItem(at: habitsURL)
        try? fileManager.removeItem(at: notificationsURL)
        try? fileManager.removeItem(at: commitmentsURL)
    }
}
