import Foundation

struct RescueInsights: Equatable, Sendable {
    var periodStart: Date
    var attempts: Int
    var completed: Int
    var abandoned: Int
    var active: Int
    var reclaimedSeconds: Double
    var leadingCue: DistractionCue?

    var resolvedAttempts: Int { completed + abandoned }
    var reclaimedMinutes: Int { Int(reclaimedSeconds / 60) }
    var completionRate: Double? {
        guard resolvedAttempts > 0 else { return nil }
        return Double(completed) / Double(resolvedAttempts)
    }

    var coachingMessage: String {
        guard attempts > 0 else {
            return "Use Rescue at the exact moment an impulse appears. The first five minutes are enough."
        }
        guard resolvedAttempts > 0 else {
            return "Your promise is still open. Press Play when you are ready; only real watch time counts."
        }
        if completionRate ?? 0 < 0.5 {
            return "Keep every Rescue at five minutes. Reduce the promise until starting feels automatic."
        }
        if completed >= 3, completionRate ?? 0 >= 0.8 {
            return "Your replacement loop is sticking. Add five minutes only after the first promise feels easy."
        }
        return "The replacement loop is forming. Finish the smallest promise before extending it."
    }
}

enum RescueInsightsEngine {
    static func weekly(
        commitments: [FocusCommitment],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> RescueInsights {
        let interval = calendar.dateInterval(of: .weekOfYear, for: now)
        let start = interval?.start ?? calendar.startOfDay(for: now)
        let end = interval?.end ?? now
        let cohort = commitments.filter {
            $0.cue.isDistraction && $0.createdAt >= start && $0.createdAt < end
        }
        let completed = cohort.filter(\.isCompleted)
        let abandoned = cohort.filter { $0.cancelledAt != nil }
        let active = cohort.filter(\.isActive)
        let counts = Dictionary(grouping: cohort, by: \.cue).mapValues(\.count)
        let leadingCue = DistractionCue.rescueChoices.max { lhs, rhs in
            let left = counts[lhs, default: 0]
            let right = counts[rhs, default: 0]
            if left == right {
                let leftIndex = DistractionCue.rescueChoices.firstIndex(of: lhs) ?? 0
                let rightIndex = DistractionCue.rescueChoices.firstIndex(of: rhs) ?? 0
                return leftIndex > rightIndex
            }
            return left < right
        }.flatMap { counts[$0, default: 0] > 0 ? $0 : nil }

        return RescueInsights(
            periodStart: start,
            attempts: cohort.count,
            completed: completed.count,
            abandoned: abandoned.count,
            active: active.count,
            reclaimedSeconds: completed.reduce(0) { $0 + $1.targetSeconds },
            leadingCue: leadingCue
        )
    }
}
