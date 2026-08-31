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

    @Test func transcriptImporterPreservesTimestampOffsets() {
        let srt = "1\n00:00:05,000 --> 00:00:08,000\nImportant idea\n"
        let value = TranscriptImporter.document(text: srt, format: "srt", podcastID: UUID(), source: .imported)
        #expect(value.segments.first?.startSeconds == 5)
        #expect(value.segments.first?.durationSeconds == 3)
    }

    @Test func supabaseDTOUsesCategoryIDWithoutSecrets() throws {
        let podcast = Podcast(title: "Episode", url: "x", youtubeVideoId: "id", categoryID: "science")
        let data = try JSONEncoder().encode(PodcastDTO(model: podcast, legacyCategory: "Science"))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("categoryID"))
        #expect(!text.localizedCaseInsensitiveContains("groq"))
    }
}
