import Combine
import Foundation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case today = "Today"
    case library = "Library"
    case progress = "Progress"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .today: "sun.max"
        case .library: "books.vertical"
        case .progress: "calendar"
        }
    }
}

enum PlayerInspectorMode: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case notes = "Notes"
    var id: String { rawValue }
}

@MainActor
final class AppViewModel: ObservableObject {
    static let shared = AppViewModel()

    @Published var podcasts: [Podcast] = []
    @Published var stats = UserStats()
    @Published var achievements: [Achievement] = []
    @Published var categories: [LearningCategory] = []
    @Published var activities: [DailyLearningActivity] = []
    @Published var summaries: [PodcastSummary] = []
    @Published var habitSettings = HabitSettings()
    @Published var notificationPreferences = NotificationPreferences()
    @Published var focusCommitments: [FocusCommitment] = []

    @Published var selectedSection: AppSection = .today
    @Published var selectedPodcast: Podcast?
    @Published var selectedCategoryID: String?
    @Published var selectedCalendarDate = Date()
    @Published var inspectorMode: PlayerInspectorMode = .summary
    @Published var inspectorPresented = true
    @Published var searchText = ""
    @Published var showAddPodcast = false
    @Published var showSettings = false
    @Published var showRescueSheet = false
    @Published var isTracking = false
    @Published var currentSessionSeconds: Double = 0
    @Published var completedCommitment: FocusCommitment?
    @Published private(set) var playbackStartRequest: PlaybackStartRequest?
    @Published var showLevelUpAlert = false
    @Published var newlyUnlockedAchievement: Achievement?
    @Published var showAchievementPopup = false
    @Published var summaryState: SummaryGenerationState = .idle
    @Published var transcriptImportPresented = false

    private let dataManager = DataManager.shared
    private var trackingTimer: Timer?
    private var saveTimer: Timer?
    private var previousLevel = 1
    private var cancellables = Set<AnyCancellable>()

    var continueWatching: [Podcast] {
        podcasts.filter { $0.hasProgress && !$0.isCompleted }
            .sorted { ($0.lastWatchedDate ?? .distantPast) > ($1.lastWatchedDate ?? .distantPast) }
    }

    var nextPodcast: Podcast? {
        continueWatching.first ?? podcasts.filter { !$0.isCompleted }.sorted { $0.dateAdded < $1.dateAdded }.first
    }

    var recentlyAdded: [Podcast] { Array(podcasts.sorted { $0.dateAdded > $1.dateAdded }.prefix(6)) }
    var completedPodcasts: [Podcast] { podcasts.filter(\.isCompleted) }
    var todayActivity: DailyLearningActivity? { activity(for: Date()) }
    var todayWatchedMinutes: Int { Int((todayActivity?.watchedSeconds ?? stats.dailySecondsWatched) / 60) }
    var todayRemainingMinutes: Int {
        max(0, Int(ceil(habitSettings.currentDailyGoalMinutes - Double(todayWatchedMinutes))))
    }

    var activeCommitment: FocusCommitment? {
        guard let podcastID = selectedPodcast?.id else { return nil }
        return focusCommitments.last { $0.podcastID == podcastID && $0.isActive }
    }

    var latestActiveCommitment: FocusCommitment? {
        focusCommitments.last(where: \.isActive)
    }

    var committedPodcast: Podcast? {
        guard let podcastID = latestActiveCommitment?.podcastID else { return nil }
        return podcasts.first { $0.id == podcastID }
    }

    var weeklyRescueInsights: RescueInsights {
        RescueInsightsEngine.weekly(commitments: focusCommitments)
    }

    var learnedDistractionPattern: DistractionPattern? {
        DistractionPatternEngine.leadingPattern(commitments: focusCommitments)
    }

    var preferredDistractionCue: DistractionCue? {
        let completed = focusCommitments.filter { $0.isCompleted && $0.cue.isDistraction }
        guard !completed.isEmpty else { return nil }
        let counts = Dictionary(grouping: completed, by: \.cue).mapValues(\.count)
        return counts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.rawValue > rhs.key.rawValue : lhs.value < rhs.value
        }?.key
    }

    var filteredPodcasts: [Podcast] {
        podcasts.filter { podcast in
            let categoryName = category(for: podcast.categoryID)?.name ?? ""
            let matchesSearch = searchText.isEmpty || podcast.title.localizedCaseInsensitiveContains(searchText)
                || categoryName.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategoryID == nil || podcast.categoryID == selectedCategoryID
            return matchesSearch && matchesCategory
        }.sorted { $0.dateAdded > $1.dateAdded }
    }

    var categoriesUsed: Set<String> {
        Set(podcasts.filter { $0.totalWatchedSeconds > 0 }.map(\.categoryID))
    }

    init() {
        loadData()
        startAutoSave()
        setupAuthObserver()
        setupNotificationRoutes()
    }

    func loadData() {
        podcasts = dataManager.loadPodcasts()
        stats = dataManager.loadStats()
        achievements = ProgressionEngine.migrateAchievements(dataManager.loadAchievements())
        categories = dataManager.loadCategories()
        activities = dataManager.loadActivities()
        summaries = dataManager.loadSummaries()
        habitSettings = dataManager.loadHabitSettings()
        notificationPreferences = dataManager.loadNotificationPreferences()
        focusCommitments = dataManager.loadFocusCommitments()

        seedMissingCategoriesAndRepairReferences()
        LearningCalendar.evaluateBuildUp(settings: &habitSettings, activities: activities, now: Date())
        stats.dailyGoalMinutes = habitSettings.currentDailyGoalMinutes
        stats.resetDailyIfNeeded()
        stats.resetWeeklyIfNeeded()
        previousLevel = stats.currentLevel.number
        saveLocalData()
        rescheduleNotifications()

        if AuthManager.shared.isAuthenticated {
            Task { await syncWithSupabase() }
        }
    }

    func saveData() {
        saveLocalData()
        guard AuthManager.shared.isAuthenticated else { return }
        let currentStats = stats
        let currentPodcasts = podcasts
        let currentCategories = categories
        let currentActivities = activities
        let currentSummaries = summaries
        Task {
            do {
                try await SupabaseClient.shared.upsertStats(currentStats)
                try await SupabaseClient.shared.upsertPodcasts(currentPodcasts, categories: currentCategories)
                try await SupabaseClient.shared.upsertCategories(currentCategories)
                try await SupabaseClient.shared.upsertActivities(currentActivities)
                try await SupabaseClient.shared.upsertSummaries(currentSummaries)
            } catch {
                print("Cloud sync deferred: \(error.localizedDescription)")
            }
        }
    }

    private func saveLocalData() {
        dataManager.savePodcasts(podcasts)
        dataManager.saveStats(stats)
        dataManager.saveAchievements(achievements)
        dataManager.saveCategories(categories)
        dataManager.saveActivities(activities)
        dataManager.saveSummaries(summaries)
        dataManager.saveHabitSettings(habitSettings)
        dataManager.saveNotificationPreferences(notificationPreferences)
        dataManager.saveFocusCommitments(focusCommitments)
    }

    private func syncWithSupabase() async {
        do {
            async let remotePodcasts = SupabaseClient.shared.fetchPodcasts()
            async let remoteStats = SupabaseClient.shared.fetchStats()
            async let remoteCategories = SupabaseClient.shared.fetchCategories()
            async let remoteActivities = SupabaseClient.shared.fetchActivities()
            async let remoteSummaries = SupabaseClient.shared.fetchSummaries()
            let result = try await (remotePodcasts, remoteStats, remoteCategories, remoteActivities, remoteSummaries)

            if !result.0.isEmpty {
                // Merge remote podcasts with any local podcasts not yet on remote
                let remoteIDs = Set(result.0.map(\.id))
                var merged = result.0
                for local in podcasts where !remoteIDs.contains(local.id) {
                    merged.append(local)
                }
                podcasts = merged
            } else if !podcasts.isEmpty {
                // Remote has no podcasts yet, push local podcasts up
                try? await SupabaseClient.shared.upsertPodcasts(podcasts, categories: categories)
            }
            if let value = result.1 { stats = value }
            if !result.2.isEmpty { categories = mergeByUpdatedAt(local: categories, remote: result.2) }
            if !result.3.isEmpty { activities = mergeByID(local: activities, remote: result.3) }
            if !result.4.isEmpty { summaries = mergeSummaries(local: summaries, remote: result.4) }
            seedMissingCategoriesAndRepairReferences()
            restoreAchievementUnlocks()
            saveLocalData()

            // If we have local podcasts/categories/stats that remote didn't have, persist them upstream
            if AuthManager.shared.isAuthenticated {
                try? await SupabaseClient.shared.upsertPodcasts(podcasts, categories: categories)
                try? await SupabaseClient.shared.upsertStats(stats)
            }
        } catch {
            print("Cloud sync unavailable; using the local learning workspace: \(error.localizedDescription)")
        }
    }

    func category(for id: String) -> LearningCategory? { categories.first { $0.id == id } }
    func summary(for podcastID: UUID) -> PodcastSummary? { summaries.first { $0.podcastID == podcastID } }
    func activity(for date: Date) -> DailyLearningActivity? {
        let key = LearningCalendar.dateKey(for: date)
        return activities.first { $0.dateKey == key }
    }

    func addPodcast(title: String, url: String, categoryID: String) {
        guard let videoID = Podcast.extractVideoId(from: url), category(for: categoryID) != nil else { return }
        podcasts.append(Podcast(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines), url: url,
            youtubeVideoId: videoID,
            thumbnailURL: "https://img.youtube.com/vi/\(videoID)/mqdefault.jpg",
            categoryID: categoryID
        ))
        stats.totalPodcastsAdded += 1
        checkAchievements()
        saveData()
        rescheduleNotifications()
    }

    func removePodcast(_ podcast: Podcast) {
        podcasts.removeAll { $0.id == podcast.id }
        summaries.removeAll { $0.podcastID == podcast.id }
        if selectedPodcast?.id == podcast.id { stopTracking(); selectedPodcast = nil }
        saveData()
        Task { try? await SupabaseClient.shared.deletePodcast(id: podcast.id) }
    }

    func selectPodcast(_ podcast: Podcast) {
        playbackStartRequest = nil
        selectedPodcast = podcast
        inspectorPresented = true
    }

    func updateNotes(for podcastID: UUID, notes: String) {
        guard let index = podcasts.firstIndex(where: { $0.id == podcastID }) else { return }
        let clean = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstNote = podcasts[index].notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !clean.isEmpty
        podcasts[index].notes = notes
        if firstNote {
            stats.totalNotesTaken += 1
            awardXP(10, activityDate: Date())
        }
        refreshSelectedPodcast()
        checkAchievements()
        saveData()
    }

    func markCompleted(_ podcast: Podcast) {
        guard let index = podcasts.firstIndex(where: { $0.id == podcast.id }), !podcasts[index].isCompleted else { return }
        podcasts[index].isCompleted = true
        stats.podcastsCompleted += 1
        awardXP(20, activityDate: Date())
        mutateTodayActivity { $0.completedPodcastIDs.insert(podcast.id) }
        refreshSelectedPodcast()
        checkAchievements()
        saveData()
        rescheduleNotifications()
    }

    /// Arms a deliberate learning block. Time starts only after the embedded player reports playback.
    func prepareCommitment(
        for podcast: Podcast,
        minutes: Int,
        cue: DistractionCue,
        launchIntent: CommitmentLaunchIntent
    ) {
        guard minutes > 0 else { return }
        if isTracking, selectedPodcast?.id != podcast.id { stopTracking() }
        for index in focusCommitments.indices where focusCommitments[index].isActive {
            focusCommitments[index].cancel()
        }
        focusCommitments.append(FocusCommitment(
            podcastID: podcast.id,
            cue: cue,
            targetSeconds: Double(minutes * 60)
        ))
        completedCommitment = nil
        selectPodcast(podcast)
        if launchIntent.requestsPlaybackStart {
            playbackStartRequest = PlaybackStartRequest(podcastID: podcast.id)
        }
        showRescueSheet = false
        saveLocalData()
        rescheduleNotifications()
    }

    func prepareRescue(cue: DistractionCue, minutes: Int) {
        guard let podcast = nextPodcast else { return }
        prepareCommitment(
            for: podcast,
            minutes: minutes,
            cue: cue,
            launchIntent: .explicitUserAction
        )
    }

    func cancelActiveCommitment() {
        guard let id = activeCommitment?.id,
              let index = focusCommitments.firstIndex(where: { $0.id == id }) else { return }
        focusCommitments[index].cancel()
        saveLocalData()
        rescheduleNotifications()
    }

    func consumePlaybackStartRequest(for podcastID: UUID) -> Bool {
        guard playbackStartRequest?.targets(podcastID) == true else { return false }
        playbackStartRequest = nil
        return true
    }

    func extendCommitment(by minutes: Int) {
        guard let podcast = selectedPodcast else { return }
        prepareCommitment(for: podcast, minutes: minutes, cue: .momentum, launchIntent: .alreadyPlaying)
    }

    func dismissCompletedCommitment() { completedCommitment = nil }

    func handlePlaybackState(podcast: Podcast, isPlaying: Bool) {
        if isPlaying {
            if isTracking, selectedPodcast?.id != podcast.id { stopTracking() }
            if !isTracking { startTracking(podcast: podcast) }
        } else if isTracking, selectedPodcast?.id == podcast.id {
            stopTracking()
        }
    }

    private func startTracking(podcast: Podcast) {
        guard !isTracking else { return }
        selectedPodcast = podcasts.first(where: { $0.id == podcast.id }) ?? podcast
        isTracking = true
        currentSessionSeconds = 0
        stats.sessionsCount += 1
        stats.resetDailyIfNeeded()
        stats.resetWeeklyIfNeeded()
        mutateTodayActivity { $0.sessions += 1 }
        Task { await NotificationManager.shared.cancelToday() }
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickTracking() }
        }
    }

    func stopTracking() {
        guard isTracking else { return }
        isTracking = false
        trackingTimer?.invalidate()
        trackingTimer = nil
        stats.longestSessionSeconds = max(stats.longestSessionSeconds, currentSessionSeconds)
        currentSessionSeconds = 0
        recomputeStreak()
        checkAchievements()
        saveData()
        rescheduleNotifications()
    }

    private func tickTracking() {
        currentSessionSeconds += 1
        stats.totalSecondsWatched += 1
        stats.dailySecondsWatched += 1
        stats.weeklySecondsWatched += 1

        if let index = podcasts.firstIndex(where: { $0.id == selectedPodcast?.id }) {
            podcasts[index].totalWatchedSeconds += 1
            podcasts[index].lastWatchedDate = Date()
            selectedPodcast = podcasts[index]
        }

        if let podcastID = selectedPodcast?.id,
           let commitmentIndex = focusCommitments.lastIndex(where: { $0.podcastID == podcastID && $0.isActive }),
           focusCommitments[commitmentIndex].recordWatchedSecond() {
            completedCommitment = focusCommitments[commitmentIndex]
            saveLocalData()
        }

        mutateTodayActivity { activity in
            activity.watchedSeconds += 1
            let newlyEarnedXP = ProgressionEngine.awardNewTrackedMinutes(activity: &activity)
            if newlyEarnedXP > 0 {
                stats.totalXP += newlyEarnedXP
                presentLevelToastIfNeeded()
            }
            if !activity.goalCompleted && activity.watchedSeconds >= activity.goalMinutes * 60 {
                activity.goalCompleted = true
                if !activity.dailyGoalXPAwarded {
                    activity.dailyGoalXPAwarded = true
                    activity.xpEarned += 25
                    stats.totalXP += 25
                    presentLevelToastIfNeeded()
                    Task { await NotificationManager.shared.cancelToday() }
                }
            }
        }
        awardWeeklyGoalIfNeeded()
    }

    func updatePlaybackPosition(for podcastID: UUID, position: Double) {
        guard let index = podcasts.firstIndex(where: { $0.id == podcastID }) else { return }
        podcasts[index].lastPlaybackPosition = position
        podcasts[index].lastWatchedDate = Date()
        refreshSelectedPodcast()
    }

    func updateDuration(for podcastID: UUID, duration: Double) {
        guard let index = podcasts.firstIndex(where: { $0.id == podcastID }) else { return }
        podcasts[index].duration = duration
        refreshSelectedPodcast()
    }

    func setDailyGoal(_ minutes: Double) {
        habitSettings.currentDailyGoalMinutes = minutes
        habitSettings.startingDailyGoalMinutes = min(habitSettings.startingDailyGoalMinutes, minutes)
        stats.dailyGoalMinutes = minutes
        mutateTodayActivity { $0.goalMinutes = minutes }
        saveData()
        rescheduleNotifications()
    }

    func setWeeklyGoal(_ hours: Double) { stats.weeklyGoalHours = hours; saveData() }

    func createCategory(name: String, symbolName: String, colorToken: String) throws {
        let value = try CategoryOperations.validatedName(name, in: categories)
        categories.append(.init(name: value, symbolName: symbolName, colorToken: colorToken, sortOrder: categories.count))
        saveData()
    }

    func updateCategory(_ category: LearningCategory) throws {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { throw CategoryValidationError.categoryNotFound }
        var updated = category
        updated.name = try CategoryOperations.validatedName(category.name, excluding: category.id, in: categories)
        updated.createdAt = categories[index].createdAt
        updated.updatedAt = Date()
        categories[index] = updated
        saveData()
    }

    func moveCategories(from offsets: IndexSet, to destination: Int) {
        categories.move(fromOffsets: offsets, toOffset: destination)
        for index in categories.indices { categories[index].sortOrder = index; categories[index].updatedAt = Date() }
        saveData()
    }

    func deleteCategory(id: String, replacementID: String?) throws {
        try CategoryOperations.delete(categoryID: id, replacementID: replacementID, categories: &categories, podcasts: &podcasts)
        saveData()
        Task { try? await SupabaseClient.shared.reassignAndDeleteCategory(id: id, replacementID: replacementID) }
    }

    func storeSummary(_ summary: PodcastSummary) {
        if let index = summaries.firstIndex(where: { $0.podcastID == summary.podcastID }) { summaries[index] = summary }
        else { summaries.append(summary) }
        unlockAchievement("first_summary")
        saveData()
    }

    func toggleAction(podcastID: UUID, actionID: UUID) {
        guard let summaryIndex = summaries.firstIndex(where: { $0.podcastID == podcastID }),
              let actionIndex = summaries[summaryIndex].actionPlan.firstIndex(where: { $0.id == actionID }) else { return }
        summaries[summaryIndex].actionPlan[actionIndex].isCompleted.toggle()
        let complete = !summaries[summaryIndex].actionPlan.isEmpty && summaries[summaryIndex].actionPlan.allSatisfy(\.isCompleted)
        if complete && !summaries[summaryIndex].actionPlanXPGranted {
            summaries[summaryIndex].actionPlanXPGranted = true
            awardXP(15, activityDate: Date())
            unlockAchievement("first_action_plan")
        }
        saveData()
    }

    func generateSummary(for podcast: Podcast, transcript: TranscriptDocument? = nil, allowAudioTranscription: Bool = false) {
        guard summaryState.isIdle else { return }
        Task { [self] in
            do {
                let summary = try await SummaryCoordinator.shared.generate(
                    for: podcast, importedTranscript: transcript, allowAudioTranscription: allowAudioTranscription,
                    progress: { [weak self] state in Task { @MainActor in self?.summaryState = state } }
                )
                storeSummary(summary)
                summaryState = .completed
            } catch SummaryPipelineError.audioConsentRequired {
                summaryState = .needsAudioConsent
            } catch SummaryPipelineError.transcriptImportRequired(let reason) {
                summaryState = .needsTranscriptImport(reason)
            } catch is CancellationError {
                summaryState = .failed("Summary generation was cancelled. Your existing summary is unchanged.")
            } catch {
                summaryState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelSummaryGeneration() { SummaryCoordinator.shared.cancel(); summaryState = .idle }

    func rescheduleNotifications() {
        let plan = NotificationPlanner.plan(
            now: Date(), preferences: notificationPreferences, activities: activities,
            currentGoalMinutes: habitSettings.currentDailyGoalMinutes,
            nextPodcast: nextPodcast, isPlaying: isTracking,
            distractionCue: preferredDistractionCue,
            distractionPattern: learnedDistractionPattern
        )
        Task { await NotificationManager.shared.replaceLearningReminders(with: plan) }
    }

    private func mutateTodayActivity(_ mutation: (inout DailyLearningActivity) -> Void) {
        let key = LearningCalendar.dateKey(for: Date())
        if let index = activities.firstIndex(where: { $0.dateKey == key }) {
            mutation(&activities[index])
        } else {
            var activity = DailyLearningActivity(dateKey: key, goalMinutes: habitSettings.currentDailyGoalMinutes)
            mutation(&activity)
            activities.append(activity)
        }
    }

    private func awardXP(_ amount: Int, activityDate: Date) {
        stats.totalXP += amount
        let key = LearningCalendar.dateKey(for: activityDate)
        if let index = activities.firstIndex(where: { $0.dateKey == key }) { activities[index].xpEarned += amount }
        else { activities.append(.init(dateKey: key, goalMinutes: habitSettings.currentDailyGoalMinutes, xpEarned: amount)) }
        presentLevelToastIfNeeded()
    }

    private func awardWeeklyGoalIfNeeded() {
        guard stats.weeklyGoalProgress >= 1 else { return }
        let week = LearningCalendar.weekKey(for: Date())
        guard habitSettings.lastWeeklyGoalAwardKey != week else { return }
        habitSettings.lastWeeklyGoalAwardKey = week
        mutateTodayActivity { $0.weeklyGoalXPAwarded = true }
        awardXP(100, activityDate: Date())
    }

    private func presentLevelToastIfNeeded() {
        let level = stats.currentLevel.number
        if level > previousLevel { previousLevel = level; showLevelUpAlert = true }
    }

    private func recomputeStreak() {
        let calendar = Calendar.current
        let qualifying = Set(activities.filter(\.qualifiesForStreak).map(\.dateKey))
        var count = 0
        var cursor = Date()
        if !qualifying.contains(LearningCalendar.dateKey(for: cursor, calendar: calendar)) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        while qualifying.contains(LearningCalendar.dateKey(for: cursor, calendar: calendar)) {
            count += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        stats.currentStreak = count
        stats.longestStreak = max(stats.longestStreak, count)
        if count > 0 { stats.lastActiveDate = Date() }
    }

    func checkAchievements() {
        let checks: [String: Bool] = [
            "first_listen": stats.totalSecondsWatched > 0, "one_hour": stats.totalHoursWatched >= 1,
            "five_hours": stats.totalHoursWatched >= 5, "ten_hours": stats.totalHoursWatched >= 10,
            "twentyfive_hours": stats.totalHoursWatched >= 25, "fifty_hours": stats.totalHoursWatched >= 50,
            "hundred_hours": stats.totalHoursWatched >= 100, "streak_3": stats.longestStreak >= 3,
            "streak_7": stats.longestStreak >= 7, "streak_14": stats.longestStreak >= 14,
            "streak_30": stats.longestStreak >= 30, "streak_100": stats.longestStreak >= 100,
            "first_note": stats.totalNotesTaken >= 1, "ten_notes": stats.totalNotesTaken >= 10,
            "twentyfive_notes": stats.totalNotesTaken >= 25, "five_podcasts": stats.totalPodcastsAdded >= 5,
            "ten_podcasts": stats.totalPodcastsAdded >= 10, "twentyfive_podcasts": stats.totalPodcastsAdded >= 25,
            "three_categories": categoriesUsed.count >= 3, "six_categories": categoriesUsed.count >= 6,
            "complete_first": stats.podcastsCompleted >= 1, "complete_five": stats.podcastsCompleted >= 5,
            "complete_ten": stats.podcastsCompleted >= 10, "weekly_goal": stats.weeklyGoalProgress >= 1,
            "daily_goal_7": stats.currentStreak >= 7, "level_5": stats.currentLevel.number >= 5,
            "level_10": stats.currentLevel.number >= 10
        ]
        for (id, shouldUnlock) in checks where shouldUnlock { unlockAchievement(id) }
    }

    private func unlockAchievement(_ id: String) {
        guard let index = achievements.firstIndex(where: { $0.id == id }), !achievements[index].isUnlocked else { return }
        achievements[index].isUnlocked = true
        achievements[index].unlockedDate = Date()
        if !stats.unlockedAchievementIds.contains(id) { stats.unlockedAchievementIds.append(id) }
        newlyUnlockedAchievement = achievements[index]
        showAchievementPopup = true
    }

    private func restoreAchievementUnlocks() {
        let ids = Set(stats.unlockedAchievementIds)
        for index in achievements.indices where ids.contains(achievements[index].id) { achievements[index].isUnlocked = true }
    }

    private func seedMissingCategoriesAndRepairReferences() {
        if categories.isEmpty { categories = LearningCategory.defaults }
        let IDs = Set(categories.map(\.id))
        if !IDs.contains(LearningCategory.generalID), let general = LearningCategory.defaults.first { categories.append(general) }
        let valid = Set(categories.map(\.id))
        for index in podcasts.indices where !valid.contains(podcasts[index].categoryID) { podcasts[index].categoryID = LearningCategory.generalID }
    }

    private func refreshSelectedPodcast() {
        guard let id = selectedPodcast?.id else { return }
        selectedPodcast = podcasts.first { $0.id == id }
    }

    private func mergeByUpdatedAt(local: [LearningCategory], remote: [LearningCategory]) -> [LearningCategory] {
        var values = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for item in remote where item.updatedAt > (values[item.id]?.updatedAt ?? .distantPast) { values[item.id] = item }
        return values.values.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func mergeByID(local: [DailyLearningActivity], remote: [DailyLearningActivity]) -> [DailyLearningActivity] {
        var values = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for item in remote { values[item.id] = item }
        return values.values.sorted { $0.dateKey < $1.dateKey }
    }

    private func mergeSummaries(local: [PodcastSummary], remote: [PodcastSummary]) -> [PodcastSummary] {
        var values = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for item in remote where item.generatedAt > (values[item.id]?.generatedAt ?? .distantPast) { values[item.id] = item }
        return Array(values.values)
    }

    private func startAutoSave() {
        saveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.saveData() }
        }
    }

    private func setupAuthObserver() {
        AuthManager.shared.$isAuthenticated.dropFirst().receive(on: RunLoop.main).sink { [weak self] authenticated in
            guard let self else { return }
            if authenticated { self.loadData() }
            else { self.stopTracking(); self.selectedPodcast = nil; self.selectedSection = .today }
        }.store(in: &cancellables)
    }

    private func setupNotificationRoutes() {
        NotificationCenter.default.publisher(for: .openPodcastFromNotification).sink { [weak self] note in
            guard let id = note.object as? UUID else { return }
            Task { @MainActor in if let podcast = self?.podcasts.first(where: { $0.id == id }) { self?.selectPodcast(podcast) } }
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: .startFiveMinutesFromNotification).sink { [weak self] note in
            guard let id = note.object as? UUID else { return }
            Task { @MainActor in
                if let podcast = self?.podcasts.first(where: { $0.id == id }) {
                    self?.prepareCommitment(
                        for: podcast,
                        minutes: 5,
                        cue: .notification,
                        launchIntent: .notificationDeepLink
                    )
                }
            }
        }.store(in: &cancellables)
    }

    isolated deinit { trackingTimer?.invalidate(); saveTimer?.invalidate() }
}

extension SummaryGenerationState {
    var isIdle: Bool {
        switch self { case .idle, .completed, .failed: true; default: false }
    }
}
