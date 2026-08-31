import Foundation

/// A lightweight, zero-dependency client to interact with the Supabase Postgrest API
final class SupabaseClient: @unchecked Sendable {
    static let shared = SupabaseClient()

    private let supabaseURL = URL(string: "https://flioaadbuwrpzmoyqypo.supabase.co")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZsaW9hYWRidXdycHptb3lxeXBvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY5ODM4NTgsImV4cCI6MjEwMjU1OTg1OH0.ixV2gCaGGMA_ZU6UgS4AaD_Ifn3GyoZaK9rKgIxAM1A"

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private init() {}

    // MARK: - Auth Helpers

    /// Safely retrieves the current access token from the @MainActor-isolated AuthManager.
    private func getAuthToken() async -> String? {
        await MainActor.run { AuthManager.shared.accessToken }
    }

    /// Safely retrieves the current user ID string from the @MainActor-isolated AuthManager.
    private func getUserId() async -> String {
        await MainActor.run { AuthManager.shared.userId?.uuidString ?? "" }
    }

    // MARK: - HTTP Helpers

    /// Builds request headers, using the user's access token when authenticated, otherwise the anon key.
    private func makeHeaders() async -> [String: String] {
        let token = await getAuthToken()
        let bearer = token ?? anonKey
        return [
            "apikey": anonKey,
            "Authorization": "Bearer \(bearer)",
            "Content-Type": "application/json"
        ]
    }

    private func sendRequest(url: URL, method: String, body: Data? = nil, customHeaders: [String: String] = [:]) async throws -> Data {
        return try await sendRequestInternal(url: url, method: method, body: body, customHeaders: customHeaders, isRetry: false)
    }

    private func sendRequestInternal(url: URL, method: String, body: Data? = nil, customHeaders: [String: String] = [:], isRetry: Bool) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method

        var headers = await makeHeaders()
        for (key, value) in customHeaders {
            headers[key] = value
        }

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // On 401, attempt one token refresh and retry
        if httpResponse.statusCode == 401 && !isRetry {
            let refreshed = await AuthManager.shared.refreshAccessToken()
            if refreshed {
                return try await sendRequestInternal(url: url, method: method, body: body, customHeaders: customHeaders, isRetry: true)
            }
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Supabase Request Failed: \(method) \(url.path) - Status \(httpResponse.statusCode) - Error: \(errorMessage)")
            throw NSError(domain: "SupabaseError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }

        return data
    }

    // MARK: - User-ID Injection

    /// Takes encoded JSON data, injects `"user_id"` into the top-level object, and re-encodes.
    private func addUserId(to data: Data) async throws -> Data {
        let userId = await getUserId()
        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        json["user_id"] = userId
        return try JSONSerialization.data(withJSONObject: json)
    }

    /// Takes encoded JSON data representing an array of objects, injects `"user_id"` into each, and re-encodes.
    private func addUserIdToArray(_ data: Data) async throws -> Data {
        let userId = await getUserId()
        guard var array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return data
        }
        for index in array.indices {
            array[index]["user_id"] = userId
        }
        return try JSONSerialization.data(withJSONObject: array)
    }

    // MARK: - Podcasts API

    func fetchPodcasts() async throws -> [Podcast] {
        let userId = await getUserId()
        let url = supabaseURL.appendingPathComponent("rest/v1/podcasts")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)")
        ]

        let data = try await sendRequest(url: components.url!, method: "GET")
        return try decoder.decode([PodcastDTO].self, from: data).map(\.model)
    }

    func upsertPodcast(_ podcast: Podcast) async throws {
        try await upsertPodcasts([podcast], categories: LearningCategory.defaults)
    }

    func upsertPodcasts(_ podcasts: [Podcast], categories: [LearningCategory]) async throws {
        guard !podcasts.isEmpty else { return }
        let url = supabaseURL.appendingPathComponent("rest/v1/podcasts")
        let names = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let rows = podcasts.map { PodcastDTO(model: $0, legacyCategory: names[$0.categoryID] ?? "General") }
        let encoded = try encoder.encode(rows)
        let data = try await addUserIdToArray(encoded)
        let headers = ["Prefer": "resolution=merge-duplicates"]
        _ = try await sendRequest(url: url, method: "POST", body: data, customHeaders: headers)
    }

    func upsertPodcasts(_ podcasts: [Podcast]) async throws {
        try await upsertPodcasts(podcasts, categories: LearningCategory.defaults)
    }

    func deletePodcast(id: UUID) async throws {
        let url = supabaseURL.appendingPathComponent("rest/v1/podcasts")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")]

        _ = try await sendRequest(url: components.url!, method: "DELETE")
    }

    // MARK: - Collections API

    func fetchCollections() async throws -> [PodcastCollection] {
        let userId = await getUserId()
        let url = supabaseURL.appendingPathComponent("rest/v1/podcast_collections")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)")
        ]
        let data = try await sendRequest(url: components.url!, method: "GET")
        return try decoder.decode([CollectionDTO].self, from: data).map(\.model)
    }

    func upsertCollections(_ collections: [PodcastCollection]) async throws {
        guard !collections.isEmpty else { return }
        let url = supabaseURL.appendingPathComponent("rest/v1/podcast_collections")
        let encoded = try encoder.encode(collections.map(CollectionDTO.init))
        let data = try await addUserIdToArray(encoded)
        _ = try await sendRequest(
            url: url,
            method: "POST",
            body: data,
            customHeaders: ["Prefer": "resolution=merge-duplicates"]
        )
    }

    func deleteCollection(id: UUID) async throws {
        let url = supabaseURL.appendingPathComponent("rest/v1/podcast_collections")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")]
        _ = try await sendRequest(url: components.url!, method: "DELETE")
    }

    // MARK: - User Stats API

    func fetchStats() async throws -> UserStats? {
        let userId = await getUserId()
        let url = supabaseURL.appendingPathComponent("rest/v1/user_stats")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "*")
        ]

        let data = try await sendRequest(url: components.url!, method: "GET")
        return try decoder.decode([UserStatsDTO].self, from: data).first?.model
    }

    func upsertStats(_ stats: UserStats) async throws {
        let userId = await getUserId()
        let url = supabaseURL.appendingPathComponent("rest/v1/user_stats")
        let encoded = try encoder.encode(UserStatsDTO(model: stats))

        // Inject the user's UUID as the `id` field for the stats row
        var json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
        json["id"] = userId
        let data = try JSONSerialization.data(withJSONObject: json)

        let headers = ["Prefer": "resolution=merge-duplicates"]
        _ = try await sendRequest(url: url, method: "POST", body: data, customHeaders: headers)
    }

    // MARK: - Learning Workspace API

    func fetchCategories() async throws -> [LearningCategory] {
        let data = try await fetchOwnedRows(table: "categories")
        return try decoder.decode([CategoryDTO].self, from: data).map(\.model)
    }

    func upsertCategories(_ categories: [LearningCategory]) async throws {
        try await upsertOwnedRows(categories.map(CategoryDTO.init), table: "categories")
    }

    func fetchActivities() async throws -> [DailyLearningActivity] {
        let data = try await fetchOwnedRows(table: "daily_learning_activity")
        return try decoder.decode([ActivityDTO].self, from: data).map(\.model)
    }

    func upsertActivities(_ activities: [DailyLearningActivity]) async throws {
        try await upsertOwnedRows(activities.map(ActivityDTO.init), table: "daily_learning_activity")
    }

    func fetchSummaries() async throws -> [PodcastSummary] {
        let data = try await fetchOwnedRows(table: "podcast_summaries")
        return try decoder.decode([SummaryDTO].self, from: data).map(\.summary)
    }

    func upsertSummaries(_ summaries: [PodcastSummary]) async throws {
        try await upsertOwnedRows(summaries.map(SummaryDTO.init), table: "podcast_summaries")
    }

    func reassignAndDeleteCategory(id: String, replacementID: String?) async throws {
        let url = supabaseURL.appendingPathComponent("rest/v1/rpc/reassign_and_delete_category")
        let parameters: [String: Any] = [
            "category_to_delete": id,
            "replacement_category": replacementID ?? NSNull()
        ]
        let body = try JSONSerialization.data(withJSONObject: parameters)
        _ = try await sendRequest(url: url, method: "POST", body: body)
    }

    private func fetchOwnedRows(table: String) async throws -> Data {
        let userID = await getUserId()
        let url = supabaseURL.appendingPathComponent("rest/v1/\(table)")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [.init(name: "select", value: "*"), .init(name: "user_id", value: "eq.\(userID)")]
        return try await sendRequest(url: components.url!, method: "GET")
    }

    private func upsertOwnedRows<T: Encodable>(_ values: [T], table: String) async throws {
        guard !values.isEmpty else { return }
        let url = supabaseURL.appendingPathComponent("rest/v1/\(table)")
        let data = try await addUserIdToArray(encoder.encode(values))
        _ = try await sendRequest(url: url, method: "POST", body: data, customHeaders: ["Prefer": "resolution=merge-duplicates"])
    }
}

struct PodcastDTO: Codable {
    var id: UUID
    var title: String
    var url: String
    var youtubeVideoId: String
    var thumbnailURL: String?
    var dateAdded: Date
    var notes: String
    var totalWatchedSeconds: Double
    var lastWatchedDate: Date?
    var lastPlaybackPosition: Double
    var isCompleted: Bool
    var completedAt: Date?
    var scheduledAt: Date?
    var collectionIDs: [UUID]?
    var categoryID: String?
    var category: String?
    var duration: Double?

    init(model: Podcast, legacyCategory: String) {
        id = model.id; title = model.title; url = model.url; youtubeVideoId = model.youtubeVideoId
        thumbnailURL = model.thumbnailURL; dateAdded = model.dateAdded; notes = model.notes
        totalWatchedSeconds = model.totalWatchedSeconds; lastWatchedDate = model.lastWatchedDate
        lastPlaybackPosition = model.lastPlaybackPosition; isCompleted = model.isCompleted
        completedAt = model.completedAt; scheduledAt = model.scheduledAt; collectionIDs = model.collectionIDs
        categoryID = model.categoryID; category = legacyCategory; duration = model.duration
    }

    var model: Podcast {
        Podcast(id: id, title: title, url: url, youtubeVideoId: youtubeVideoId, thumbnailURL: thumbnailURL,
                dateAdded: dateAdded, notes: notes, totalWatchedSeconds: totalWatchedSeconds,
                lastWatchedDate: lastWatchedDate, lastPlaybackPosition: lastPlaybackPosition,
                isCompleted: isCompleted, completedAt: completedAt, scheduledAt: scheduledAt,
                collectionIDs: collectionIDs ?? [],
                categoryID: categoryID ?? LearningCategory.stableID(forLegacyName: category ?? "General"), duration: duration)
    }
}

struct CollectionDTO: Codable {
    var id: UUID
    var title: String
    var sourcePlaylistID: String
    var sourceURL: String
    var dateAdded: Date
    var sortOrder: Int
    var videoIDs: [String]

    init(_ model: PodcastCollection) {
        id = model.id
        title = model.title
        sourcePlaylistID = model.sourcePlaylistID
        sourceURL = model.sourceURL
        dateAdded = model.dateAdded
        sortOrder = model.sortOrder
        videoIDs = model.videoIDs
    }

    var model: PodcastCollection {
        .init(id: id, title: title, sourcePlaylistID: sourcePlaylistID, sourceURL: sourceURL, dateAdded: dateAdded, sortOrder: sortOrder, videoIDs: videoIDs)
    }
}

struct UserStatsDTO: Codable {
    var id: String; var totalSecondsWatched: Double; var currentStreak: Int; var longestStreak: Int
    var lastActiveDate: Date?; var totalXP: Int; var weeklyGoalHours: Double; var dailyGoalMinutes: Double
    var weeklySecondsWatched: Double; var dailySecondsWatched: Double; var weekStartDate: Date?; var dayStartDate: Date?
    var unlockedAchievementIds: [String]; var podcastsCompleted: Int; var totalNotesTaken: Int
    var totalPodcastsAdded: Int; var sessionsCount: Int; var longestSessionSeconds: Double
    init(model: UserStats) {
        id = model.id; totalSecondsWatched = model.totalSecondsWatched; currentStreak = model.currentStreak
        longestStreak = model.longestStreak; lastActiveDate = model.lastActiveDate; totalXP = model.totalXP
        weeklyGoalHours = model.weeklyGoalHours; dailyGoalMinutes = model.dailyGoalMinutes
        weeklySecondsWatched = model.weeklySecondsWatched; dailySecondsWatched = model.dailySecondsWatched
        weekStartDate = model.weekStartDate; dayStartDate = model.dayStartDate
        unlockedAchievementIds = model.unlockedAchievementIds; podcastsCompleted = model.podcastsCompleted
        totalNotesTaken = model.totalNotesTaken; totalPodcastsAdded = model.totalPodcastsAdded
        sessionsCount = model.sessionsCount; longestSessionSeconds = model.longestSessionSeconds
    }
    var model: UserStats {
        UserStats(id: id, totalSecondsWatched: totalSecondsWatched, currentStreak: currentStreak,
                  longestStreak: longestStreak, lastActiveDate: lastActiveDate, totalXP: totalXP,
                  weeklyGoalHours: weeklyGoalHours, dailyGoalMinutes: dailyGoalMinutes,
                  weeklySecondsWatched: weeklySecondsWatched, dailySecondsWatched: dailySecondsWatched,
                  weekStartDate: weekStartDate, dayStartDate: dayStartDate,
                  unlockedAchievementIds: unlockedAchievementIds, podcastsCompleted: podcastsCompleted,
                  totalNotesTaken: totalNotesTaken, totalPodcastsAdded: totalPodcastsAdded,
                  sessionsCount: sessionsCount, longestSessionSeconds: longestSessionSeconds)
    }
}

struct CategoryDTO: Codable {
    var id: String; var name: String; var symbolName: String; var colorToken: String
    var sortOrder: Int; var createdAt: Date; var updatedAt: Date
    init(_ model: LearningCategory) {
        id = model.id; name = model.name; symbolName = model.symbolName; colorToken = model.colorToken
        sortOrder = model.sortOrder; createdAt = model.createdAt; updatedAt = model.updatedAt
    }
    var model: LearningCategory { .init(id: id, name: name, symbolName: symbolName, colorToken: colorToken, sortOrder: sortOrder, createdAt: createdAt, updatedAt: updatedAt) }
}

struct ActivityDTO: Codable {
    var dateKey: String; var watchedSeconds: Double; var sessions: Int; var goalMinutes: Double; var goalCompleted: Bool
    var xpEarned: Int; var completedPodcastIDs: [UUID]; var xpAwardedMinutes: Int
    var dailyGoalXPAwarded: Bool; var weeklyGoalXPAwarded: Bool
    init(_ model: DailyLearningActivity) {
        dateKey = model.dateKey; watchedSeconds = model.watchedSeconds; sessions = model.sessions
        goalMinutes = model.goalMinutes; goalCompleted = model.goalCompleted; xpEarned = model.xpEarned
        completedPodcastIDs = Array(model.completedPodcastIDs); xpAwardedMinutes = model.xpAwardedMinutes
        dailyGoalXPAwarded = model.dailyGoalXPAwarded; weeklyGoalXPAwarded = model.weeklyGoalXPAwarded
    }
    var model: DailyLearningActivity { .init(dateKey: dateKey, watchedSeconds: watchedSeconds, sessions: sessions, goalMinutes: goalMinutes, goalCompleted: goalCompleted, xpEarned: xpEarned, completedPodcastIDs: Set(completedPodcastIDs), xpAwardedMinutes: xpAwardedMinutes, dailyGoalXPAwarded: dailyGoalXPAwarded, weeklyGoalXPAwarded: weeklyGoalXPAwarded) }
}

struct SummaryDTO: Codable {
    var podcastID: UUID; var brief: String; var keyTopics: [PodcastSummary.Topic]
    var majorTakeaways: [PodcastSummary.Takeaway]; var actionPlan: [PodcastSummary.ActionStep]
    var dynamicSections: [PodcastSummary.Section]?
    var generatedAt: Date; var transcriptSource: TranscriptSource; var modelName: String; var actionPlanXPGranted: Bool
    enum CodingKeys: String, CodingKey { case podcastID, brief, keyTopics, majorTakeaways, actionPlan; case dynamicSections = "dynamic_sections"; case generatedAt, transcriptSource; case modelName = "model"; case actionPlanXPGranted }
    init(_ value: PodcastSummary) {
        podcastID = value.podcastID; brief = value.brief; keyTopics = value.keyTopics
        majorTakeaways = value.majorTakeaways; actionPlan = value.actionPlan; dynamicSections = value.sections; generatedAt = value.generatedAt
        transcriptSource = value.transcriptSource; modelName = value.model; actionPlanXPGranted = value.actionPlanXPGranted
    }
    var summary: PodcastSummary { .init(podcastID: podcastID, brief: brief, keyTopics: keyTopics, majorTakeaways: majorTakeaways, actionPlan: actionPlan, sections: dynamicSections ?? [], generatedAt: generatedAt, transcriptSource: transcriptSource, model: modelName, actionPlanXPGranted: actionPlanXPGranted) }
}
