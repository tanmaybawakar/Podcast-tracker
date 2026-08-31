import Foundation
import Testing
@testable import PodcastTracker

@Suite("Category migration and management")
struct CategoryTests {
    @Test func legacyPodcastCategoryDecodesToStableID() throws {
        let json = #"{"title":"Legacy","url":"https://youtu.be/dQw4w9WgXcQ","youtubeVideoId":"dQw4w9WgXcQ","category":"Self Improvement"}"#.data(using: .utf8)!
        let podcast = try JSONDecoder().decode(Podcast.self, from: json)
        #expect(podcast.categoryID == "self-improvement")
    }

    @Test func duplicateAndEmptyNamesAreRejected() {
        let categories = LearningCategory.defaults
        #expect(throws: CategoryValidationError.emptyName) { try CategoryOperations.validatedName("  ", in: categories) }
        #expect(throws: CategoryValidationError.duplicateName) { try CategoryOperations.validatedName("technology", in: categories) }
    }

    @Test func deletingUsedCategoryReassignsAtomically() throws {
        var categories = Array(LearningCategory.defaults.prefix(2))
        var podcasts = [Podcast(title: "Episode", url: "x", youtubeVideoId: "id", categoryID: "technology")]
        try CategoryOperations.delete(categoryID: "technology", replacementID: "general", categories: &categories, podcasts: &podcasts)
        #expect(categories.map(\.id) == ["general"])
        #expect(podcasts[0].categoryID == "general")
    }

    @Test func finalCategoryCannotBeDeleted() {
        var categories = [LearningCategory.defaults[0]]
        var podcasts: [Podcast] = []
        #expect(throws: CategoryValidationError.lastCategory) {
            try CategoryOperations.delete(categoryID: "general", replacementID: nil, categories: &categories, podcasts: &podcasts)
        }
    }
}

@Suite("Adaptive learning")
struct HabitTests {
    private var calendar: Calendar { var value = Calendar(identifier: .iso8601); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: "\(value)T12:00:00Z")! }

    @Test func fiveOfSevenRaisesGoalOnceAndCaps() {
        var settings = HabitSettings(currentDailyGoalMinutes: 55, startingDailyGoalMinutes: 15, targetDailyGoalMinutes: 60)
        let activity = (3...7).map { DailyLearningActivity(dateKey: "2026-08-0\($0)", watchedSeconds: 900, goalMinutes: 15, goalCompleted: true) }
        LearningCalendar.evaluateBuildUp(settings: &settings, activities: activity, now: date("2026-08-10"), calendar: calendar)
        #expect(settings.currentDailyGoalMinutes == 60)
        LearningCalendar.evaluateBuildUp(settings: &settings, activities: activity, now: date("2026-08-11"), calendar: calendar)
        #expect(settings.currentDailyGoalMinutes == 60)
    }

    @Test func fourOfSevenHolds() {
        var settings = HabitSettings()
        let activity = (3...6).map { DailyLearningActivity(dateKey: "2026-08-0\($0)", watchedSeconds: 900, goalMinutes: 15, goalCompleted: true) }
        LearningCalendar.evaluateBuildUp(settings: &settings, activities: activity, now: date("2026-08-10"), calendar: calendar)
        #expect(settings.currentDailyGoalMinutes == 15)
    }

    @Test func fiveMinutesQualifiesForStreak() {
        #expect(DailyLearningActivity(dateKey: "x", watchedSeconds: 299, goalMinutes: 30).qualifiesForStreak == false)
        #expect(DailyLearningActivity(dateKey: "x", watchedSeconds: 300, goalMinutes: 30).qualifiesForStreak)
    }

    @Test func trackedMinuteXPIsIdempotent() {
        var activity = DailyLearningActivity(dateKey: "2026-08-18", watchedSeconds: 125, goalMinutes: 30)
        #expect(ProgressionEngine.awardNewTrackedMinutes(activity: &activity) == 2)
        #expect(ProgressionEngine.awardNewTrackedMinutes(activity: &activity) == 0)
        activity.watchedSeconds = 180
        #expect(ProgressionEngine.awardNewTrackedMinutes(activity: &activity) == 1)
        #expect(activity.xpEarned == 3)
    }

    @Test func achievementMigrationPreservesValidUnlocksAndDropsMutableLegacyBreadth() {
        var valid = Achievement.allAchievements.first { $0.id == "first_listen" }!
        valid.isUnlocked = true
        let legacy = Achievement(id: "all_categories", title: "Old", description: "Old", iconName: "globe", xpReward: 500, category: .explorer, isUnlocked: true)
        let migrated = ProgressionEngine.migrateAchievements([valid, legacy])
        #expect(migrated.first(where: { $0.id == "first_listen" })?.isUnlocked == true)
        #expect(migrated.contains(where: { $0.id == "all_categories" }) == false)
        #expect(migrated.contains(where: { $0.id == "six_categories" }))
    }
}

@Suite("Notification planning")
struct NotificationTests {
    @Test func plansThreeStagesWithoutDuplicates() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-08-18T08:00:00Z")!
        let podcast = Podcast(title: "Learn", url: "x", youtubeVideoId: "id")
        let result = NotificationPlanner.plan(now: now, preferences: .init(), activities: [], currentGoalMinutes: 30, nextPodcast: podcast, isPlaying: false, calendar: calendar)
        #expect(Set(result.map(\.id)).count == result.count)
        #expect(result.filter { Calendar.current.isDate($0.fireDate, inSameDayAs: now) }.count <= 3)
        #expect(Set(result.map(\.stage)).isSuperset(of: [.morning, .afternoon, .evening]))
    }

    @Test func goalAndPlaybackSuppressNotifications() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-08-18T08:00:00Z")!
        let podcast = Podcast(title: "Learn", url: "x", youtubeVideoId: "id")
        #expect(NotificationPlanner.plan(now: now, preferences: .init(), activities: [], currentGoalMinutes: 30, nextPodcast: podcast, isPlaying: true, calendar: calendar).isEmpty)
        let today = DailyLearningActivity(dateKey: LearningCalendar.dateKey(for: now, calendar: calendar), goalMinutes: 30, goalCompleted: true)
        let result = NotificationPlanner.plan(now: now, preferences: .init(), activities: [today], currentGoalMinutes: 30, nextPodcast: podcast, isPlaying: false, calendar: calendar)
        #expect(result.allSatisfy { !calendar.isDate($0.fireDate, inSameDayAs: now) })
    }

    @Test func reminderCopyLearnsTheCompletedRescueCue() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-08-18T08:00:00Z")!
        let podcast = Podcast(title: "Learn", url: "x", youtubeVideoId: "id")
        let result = NotificationPlanner.plan(
            now: now, preferences: .init(), activities: [], currentGoalMinutes: 30,
            nextPodcast: podcast, isPlaying: false, distractionCue: .gaming, calendar: calendar
        )
        #expect(result.contains { $0.stage == .afternoon && $0.title.contains("game") })
        #expect(result.contains { $0.stage == .evening && $0.body.localizedCaseInsensitiveContains("gaming") })
    }

    @Test func adaptiveRescueReplacesANearbyGenericReminder() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-08-24T08:00:00Z")!
        let podcast = Podcast(title: "Learn", url: "x", youtubeVideoId: "id")
        let pattern = DistractionPattern(cue: .gaming, weekday: 3, hour: 19, minute: 10, observations: 3)
        let result = NotificationPlanner.plan(
            now: now, preferences: .init(), activities: [], currentGoalMinutes: 30,
            nextPodcast: podcast, isPlaying: false, distractionPattern: pattern, calendar: calendar
        )
        let adaptive = result.filter { $0.stage == .rescue }
        #expect(adaptive.count == 1)
        #expect(adaptive[0].title.localizedCaseInsensitiveContains("gaming"))
        #expect(result.filter { calendar.isDate($0.fireDate, inSameDayAs: adaptive[0].fireDate) }.count == 3)
        #expect(Set(result.map(\.id)).count == result.count)
    }

    @Test func adaptiveRescueRespectsQuietHours() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-08-24T08:00:00Z")!
        let podcast = Podcast(title: "Learn", url: "x", youtubeVideoId: "id")
        var preferences = NotificationPreferences()
        preferences.quietHoursEnabled = true
        preferences.quietHoursStart = .init(hour: 18, minute: 0)
        preferences.quietHoursEnd = .init(hour: 21, minute: 0)
        let pattern = DistractionPattern(cue: .gaming, weekday: 3, hour: 19, minute: 10, observations: 3)
        let result = NotificationPlanner.plan(
            now: now, preferences: preferences, activities: [], currentGoalMinutes: 30,
            nextPodcast: podcast, isPlaying: false, distractionPattern: pattern, calendar: calendar
        )
        #expect(!result.contains { $0.stage == .rescue })
    }
}

@Suite("Distraction rescue commitments")
struct FocusCommitmentTests {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    @Test func menuBarTitlesStayCompact() {
        let title = MenuBarText.shortened("Continue A Very Long Educational Podcast Episode Title")
        #expect(title.count == 30)
        #expect(title.hasSuffix("..."))
        #expect(MenuBarText.shortened("Continue Biology") == "Continue Biology")
    }

    @Test func onlyExplicitActionsRequestImmediatePlayback() {
        #expect(CommitmentLaunchIntent.explicitUserAction.requestsPlaybackStart)
        #expect(!CommitmentLaunchIntent.notificationDeepLink.requestsPlaybackStart)
        #expect(!CommitmentLaunchIntent.alreadyPlaying.requestsPlaybackStart)
    }

    @Test func playbackStartRequestTargetsOnlyItsEpisode() {
        let target = UUID()
        let request = PlaybackStartRequest(podcastID: target)
        #expect(request.targets(target))
        #expect(!request.targets(UUID()))
    }

    @Test func resumePositionIsSafeForFreshUnknownAndCompletedMedia() {
        #expect(PlaybackResumePosition.target(requested: 0, duration: 100) == 0)
        #expect(PlaybackResumePosition.target(requested: 36, duration: nil) == 36)
        #expect(PlaybackResumePosition.target(requested: 120, duration: 100) == 99)
        #expect(PlaybackResumePosition.target(requested: .nan, duration: 100) == 0)
    }

    @MainActor
    @Test func playerKeepsAStartRequestPendingUntilPlaybackBegins() {
        let controller = PlayerController()
        controller.requestPlaybackStart()
        #expect(controller.isPlaybackStartPending)

        controller.playerStateDidChange(isPlaying: false)
        #expect(controller.isPlaybackStartPending)

        controller.playerStateDidChange(isPlaying: true)
        #expect(!controller.isPlaybackStartPending)
    }

    @Test func commitmentAdvancesOnlyWhenPlaybackRecordsTime() {
        var commitment = FocusCommitment(podcastID: UUID(), cue: .scrolling, targetSeconds: 3)
        #expect(commitment.watchedSeconds == 0)
        #expect(commitment.isActive)
        #expect(commitment.recordWatchedSecond() == false)
        #expect(commitment.watchedSeconds == 1)
    }

    @Test func completionTransitionIsNonRepeatable() {
        var commitment = FocusCommitment(podcastID: UUID(), cue: .anime, targetSeconds: 2)
        #expect(commitment.recordWatchedSecond() == false)
        let didComplete = commitment.recordWatchedSecond()
        #expect(didComplete)
        #expect(commitment.isCompleted)
        #expect(commitment.recordWatchedSecond() == false)
        #expect(commitment.watchedSeconds == 2)
    }

    @Test func partialProgressPersistsAndCancellationFreezesIt() throws {
        var commitment = FocusCommitment(podcastID: UUID(), cue: .streaming, targetSeconds: 300)
        _ = commitment.recordWatchedSecond()
        let restored = try JSONDecoder().decode(FocusCommitment.self, from: JSONEncoder().encode(commitment))
        #expect(restored.watchedSeconds == 1)

        var cancelled = restored
        cancelled.cancel()
        #expect(cancelled.isActive == false)
        #expect(cancelled.recordWatchedSecond() == false)
        #expect(cancelled.watchedSeconds == 1)
    }

    @Test func weeklyInsightsSeparateCompletedAbandonedAndActiveRescues() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let podcastID = UUID()
        let completedAt = date("2026-08-18T09:05:00Z")
        let commitments = [
            FocusCommitment(
                podcastID: podcastID, cue: .scrolling, targetSeconds: 300, watchedSeconds: 300,
                createdAt: date("2026-08-18T09:00:00Z"), completedAt: completedAt
            ),
            FocusCommitment(
                podcastID: podcastID, cue: .gaming, targetSeconds: 300,
                createdAt: date("2026-08-18T10:00:00Z"), cancelledAt: date("2026-08-18T10:01:00Z")
            ),
            FocusCommitment(
                podcastID: podcastID, cue: .streaming, targetSeconds: 300,
                createdAt: date("2026-08-19T10:00:00Z")
            ),
            FocusCommitment(
                podcastID: podcastID, cue: .today, targetSeconds: 300, watchedSeconds: 300,
                createdAt: date("2026-08-18T11:00:00Z"), completedAt: date("2026-08-18T11:05:00Z")
            ),
            FocusCommitment(
                podcastID: podcastID, cue: .scrolling, targetSeconds: 300, watchedSeconds: 300,
                createdAt: date("2026-08-10T09:00:00Z"), completedAt: date("2026-08-10T09:05:00Z")
            )
        ]

        let insights = RescueInsightsEngine.weekly(
            commitments: commitments,
            now: date("2026-08-19T12:00:00Z"),
            calendar: calendar
        )
        #expect(insights.attempts == 3)
        #expect(insights.completed == 1)
        #expect(insights.abandoned == 1)
        #expect(insights.active == 1)
        #expect(insights.reclaimedMinutes == 5)
        #expect(insights.completionRate == 0.5)
        #expect(insights.leadingCue == .scrolling)
    }

    @Test func weeklyInsightsRespectLocalWeekBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 19_800)!
        calendar.firstWeekday = 2
        let podcastID = UUID()
        let commitments = [
            FocusCommitment(
                podcastID: podcastID, cue: .scrolling, targetSeconds: 300,
                createdAt: date("2026-08-16T18:15:00Z")
            ),
            FocusCommitment(
                podcastID: podcastID, cue: .gaming, targetSeconds: 300,
                createdAt: date("2026-08-16T18:45:00Z")
            )
        ]
        let insights = RescueInsightsEngine.weekly(
            commitments: commitments,
            now: date("2026-08-16T19:00:00Z"),
            calendar: calendar
        )
        #expect(insights.attempts == 1)
        #expect(insights.leadingCue == .gaming)
    }

    @Test func coachingReducesDifficultyBeforeSuggestingExtension() {
        let podcastID = UUID()
        let now = date("2026-08-19T12:00:00Z")
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let failed = (0..<3).map { index in
            FocusCommitment(
                podcastID: podcastID, cue: .scrolling, targetSeconds: 300,
                createdAt: date("2026-08-18T0\(index + 1):00:00Z"),
                cancelledAt: date("2026-08-18T0\(index + 1):01:00Z")
            )
        }
        #expect(RescueInsightsEngine.weekly(commitments: failed, now: now, calendar: calendar).coachingMessage.contains("five minutes"))

        let completed = (0..<3).map { index in
            FocusCommitment(
                podcastID: podcastID, cue: .scrolling, targetSeconds: 300, watchedSeconds: 300,
                createdAt: date("2026-08-18T1\(index):00:00Z"),
                completedAt: date("2026-08-18T1\(index):05:00Z")
            )
        }
        #expect(RescueInsightsEngine.weekly(commitments: completed, now: now, calendar: calendar).coachingMessage.contains("sticking"))
    }

    @Test func repeatedDistractionWindowProducesOneProactivePattern() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let podcastID = UUID()
        let commitments = [
            FocusCommitment(podcastID: podcastID, cue: .gaming, targetSeconds: 300, createdAt: date("2026-08-04T19:20:00Z")),
            FocusCommitment(podcastID: podcastID, cue: .gaming, targetSeconds: 300, createdAt: date("2026-08-11T19:25:00Z")),
            FocusCommitment(podcastID: podcastID, cue: .gaming, targetSeconds: 300, createdAt: date("2026-08-18T19:10:00Z")),
            FocusCommitment(podcastID: podcastID, cue: .scrolling, targetSeconds: 300, createdAt: date("2026-08-18T09:00:00Z"))
        ]
        let pattern = DistractionPatternEngine.leadingPattern(
            commitments: commitments,
            now: date("2026-08-19T12:00:00Z"),
            calendar: calendar
        )
        #expect(pattern?.cue == .gaming)
        #expect(pattern?.weekday == 3)
        #expect(pattern?.hour == 19)
        #expect(pattern?.minute == 10)
        #expect(pattern?.observations == 3)
    }

    @Test func sparseOrStaleDistractionsDoNotCreateAPattern() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let podcastID = UUID()
        let commitments = [
            FocusCommitment(podcastID: podcastID, cue: .gaming, targetSeconds: 300, createdAt: date("2026-08-11T19:20:00Z")),
            FocusCommitment(podcastID: podcastID, cue: .gaming, targetSeconds: 300, createdAt: date("2026-08-18T19:10:00Z")),
            FocusCommitment(podcastID: podcastID, cue: .gaming, targetSeconds: 300, createdAt: date("2026-07-01T19:15:00Z"))
        ]
        #expect(DistractionPatternEngine.leadingPattern(
            commitments: commitments,
            now: date("2026-08-19T12:00:00Z"),
            calendar: calendar
        ) == nil)
    }
}

@Suite("AI and sync contracts")
struct ContractTests {
    @Test func strictSummaryPayloadDecodes() throws {
        let data = #"{"brief":"Brief","keyTopics":[{"title":"Topic","explanation":"Why","timestampSeconds":12}],"majorTakeaways":[{"title":"Takeaway","explanation":"Because"}],"actionPlan":[{"title":"Do it","detail":"Today"}]}"#.data(using: .utf8)!
        let value = try JSONDecoder().decode(GroqSummaryPayload.self, from: data)
        #expect(value.keyTopics[0].timestampSeconds == 12)
        #expect(value.actionPlan.count == 1)
    }

    @Test func quirkyTiersUseThreeDistinctModelsAndStrengths() {
        #expect(Set(QuirkyModel.allCases.map(\.modelID)).count == 3)
        #expect(QuirkyModel.deep.reasoningEffort == "high")
        #expect(QuirkyModel.balanced.reasoningEffort == "medium")
        #expect(QuirkyModel.instant.reasoningEffort == "low")
    }

    @Test func quirkyPromptGroundsAdviceAndProtectsProjectContext() {
        let prompt = QuirkyPrompt.system(episodeTitle: "Reddit strategy", transcript: "[1:10] Seven steps")
        #expect(prompt.contains("transcript as the primary source of truth"))
        #expect(prompt.contains("never assume which project"))
        #expect(prompt.contains("action, deliverable, constraint, and success check"))
        #expect(prompt.contains("[1:10] Seven steps"))
    }

    @Test func quirkyContextCapsTranscriptAndPrioritizesQuestionMatches() {
        let filler = String(repeating: "Unrelated transcript line.\n", count: 1_000)
        let transcript = filler + "[12:30] The launch plan is to validate with ten customers.\n" + filler
        let excerpt = QuirkyContext.transcriptExcerpt(transcript, for: "What is the launch plan?")
        #expect(excerpt.count <= QuirkyContext.maximumTranscriptCharacters)
        #expect(excerpt.contains("validate with ten customers"))
    }

    @Test func quirkyContextCapsConversationHistory() {
        let history = (0..<8).map { (role: "user", content: String(repeating: "x", count: 2_000) + "\($0)") }
        let compact = QuirkyContext.recentHistory(history)
        #expect(compact.count == QuirkyContext.maximumHistoryMessages)
        #expect(compact.allSatisfy { ($0["content"]?.count ?? 0) <= QuirkyContext.maximumHistoryCharacters })
    }


    @Test func transcriptImporterPreservesTimestampOffsets() {
        let srt = "1\n00:00:05,000 --> 00:00:08,000\nImportant idea\n"
        let value = TranscriptImporter.document(text: srt, format: "srt", podcastID: UUID(), source: .imported)
        #expect(value.segments.first?.startSeconds == 5)
        #expect(value.segments.first?.durationSeconds == 3)
    }

    @Test func transcriptAPIResponsePreservesTimestampedSegments() throws {
        let data = #"{"transcript":[{"text":"First point","start":12.5,"duration":3.25}]}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(TranscriptAPIResponse.self, from: data)
        #expect(response.transcript.first?.text == "First point")
        #expect(response.transcript.first?.start == 12.5)
        #expect(response.transcript.first?.duration == 3.25)
    }

    @Test func supabaseDTOUsesCategoryIDWithoutSecrets() throws {
        let collectionID = UUID()
        let podcast = Podcast(
            title: "Episode", url: "x", youtubeVideoId: "id",
            completedAt: Date(timeIntervalSince1970: 100),
            scheduledAt: Date(timeIntervalSince1970: 200),
            collectionIDs: [collectionID], categoryID: "science"
        )
        let data = try JSONEncoder().encode(PodcastDTO(model: podcast, legacyCategory: "Science"))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("categoryID"))
        #expect(text.contains("completedAt"))
        #expect(text.contains("scheduledAt"))
        #expect(text.contains(collectionID.uuidString))
        #expect(!text.localizedCaseInsensitiveContains("groq"))
        #expect(!text.contains("fileName"))
        #expect(!text.contains("byteCount"))
        #expect(!text.contains("resolutionHeight"))
    }
}

@Suite("Downloads, scheduling, and collections")
struct LibraryManagementTests {
    @Test func cloudMergeRetainsTheNewestResumePosition() {
        let id = UUID()
        let local = Podcast(
            id: id, title: "Episode", url: "x", youtubeVideoId: "dQw4w9WgXcQ",
            lastWatchedDate: Date(timeIntervalSince1970: 200), lastPlaybackPosition: 82
        )
        let remote = Podcast(
            id: id, title: "Episode", url: "x", youtubeVideoId: "dQw4w9WgXcQ",
            lastWatchedDate: Date(timeIntervalSince1970: 100), lastPlaybackPosition: 31
        )

        #expect(Podcast.mergedForSync(local: local, remote: remote).lastPlaybackPosition == 82)
    }

    @Test func cloudMergeUsesNewerRemoteProgress() {
        let id = UUID()
        let local = Podcast(
            id: id, title: "Episode", url: "x", youtubeVideoId: "dQw4w9WgXcQ",
            lastWatchedDate: Date(timeIntervalSince1970: 100), lastPlaybackPosition: 82
        )
        let remote = Podcast(
            id: id, title: "Episode", url: "x", youtubeVideoId: "dQw4w9WgXcQ",
            lastWatchedDate: Date(timeIntervalSince1970: 200), lastPlaybackPosition: 143
        )

        #expect(Podcast.mergedForSync(local: local, remote: remote).lastPlaybackPosition == 143)
    }

    @Test func oldPodcastPayloadDefaultsNewFieldsSafely() throws {
        let data = #"{"title":"Legacy","url":"x","youtubeVideoId":"dQw4w9WgXcQ","isCompleted":false}"#.data(using: .utf8)!
        let podcast = try JSONDecoder().decode(Podcast.self, from: data)
        #expect(podcast.completedAt == nil)
        #expect(podcast.scheduledAt == nil)
        #expect(podcast.collectionIDs.isEmpty)
    }

    @Test func downloadDefaultsUseEightGBAnd1080p() {
        let settings = DownloadSettings()
        #expect(settings.maximumStorageBytes == 8 * 1_024 * 1_024 * 1_024)
        #expect(settings.quality == .high1080)
        #expect(DownloadQuality.saver480.formatSelector.contains("height<=480"))
        #expect(DownloadQuality.standard720.formatSelector.contains("height<=720"))
        #expect(DownloadQuality.high1080.formatSelector.contains("height<=1080"))
    }

    @Test func redownloadingACompletedEpisodeIsManuallyRetained() {
        #expect(LocalMediaStore.retentionForNewDownload(completedAt: nil) == .untilCompleted)
        #expect(LocalMediaStore.retentionForNewDownload(completedAt: Date()) == .manual)
    }

    @MainActor
    @Test func hardCapRejectsANewDownloadBeforeNetworkWork() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "PodTrackioCapTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let occupyingFile = root.appending(path: "aaaaaaaaaaa.mp4")
        _ = FileManager.default.createFile(atPath: occupyingFile.path, contents: Data())
        let handle = try FileHandle(forWritingTo: occupyingFile)
        try handle.truncate(atOffset: UInt64(DownloadSettings.storageLimitBytes))
        try handle.close()

        let store = LocalMediaStore(rootURL: root)
        do {
            _ = try await store.download(videoID: "dQw4w9WgXcQ", completedAt: nil)
            Issue.record("Expected the hard storage cap to reject the download")
        } catch let error as LocalMediaStore.MediaError {
            #expect(error == .storageLimitReached)
        }
    }

    @Test func scheduledNotificationHasStableIndependentIdentifier() {
        let id = UUID()
        let item = ScheduledPodcastNotification(podcastID: id, title: "Episode", fireDate: Date())
        #expect(item.id == "scheduled.\(id.uuidString)")
    }

    @Test func collectionKeepsPlaylistOrder() {
        let collection = PodcastCollection(
            title: "Course", sourcePlaylistID: "PL123", sourceURL: "https://youtube.com/playlist?list=PL123",
            videoIDs: ["aaaaaaaaaaa", "bbbbbbbbbbb"]
        )
        #expect(collection.videoIDs == ["aaaaaaaaaaa", "bbbbbbbbbbb"])
    }

    @MainActor
    @Test func completedDownloadExpiresWithoutTouchingUserStorage() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "PodTrackioCleanupTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let videoID = "dQw4w9WgXcQ"
        let file = root.appending(path: "\(videoID).mp4")
        try Data(repeating: 1, count: 1_000_001).write(to: file)

        let store = LocalMediaStore(rootURL: root)
        let completion = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        let podcast = Podcast(
            title: "Done", url: "x", youtubeVideoId: videoID,
            isCompleted: true, completedAt: completion
        )
        store.reconcile(with: [podcast])
        #expect(store.records[videoID] == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
