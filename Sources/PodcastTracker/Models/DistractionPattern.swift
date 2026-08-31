import Foundation

struct DistractionPattern: Equatable, Sendable {
    var cue: DistractionCue
    var weekday: Int
    var hour: Int
    var minute: Int
    var observations: Int

    func nextFireDate(after now: Date, calendar: Calendar = .current) -> Date? {
        for dayOffset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now),
                  calendar.component(.weekday, from: day) == weekday else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            if let candidate = calendar.date(from: components), candidate > now {
                return candidate
            }
        }
        return nil
    }
}

enum DistractionPatternEngine {
    private struct Bucket: Hashable {
        var cue: DistractionCue
        var weekday: Int
        var twoHourBlock: Int
    }

    static func leadingPattern(
        commitments: [FocusCommitment],
        now: Date = Date(),
        calendar: Calendar = .current,
        minimumObservations: Int = 3
    ) -> DistractionPattern? {
        guard minimumObservations > 0,
              let lookbackStart = calendar.date(byAdding: .day, value: -28, to: now) else { return nil }

        let recent = commitments.filter {
            $0.cue.isDistraction && $0.createdAt >= lookbackStart && $0.createdAt < now
        }
        let groups = Dictionary(grouping: recent) { commitment in
            let hour = calendar.component(.hour, from: commitment.createdAt)
            return Bucket(
                cue: commitment.cue,
                weekday: calendar.component(.weekday, from: commitment.createdAt),
                twoHourBlock: hour / 2
            )
        }

        let candidates = groups.filter { $0.value.count >= minimumObservations }
        guard let winner = candidates.sorted(by: { lhs, rhs in
            if lhs.value.count != rhs.value.count { return lhs.value.count > rhs.value.count }
            let leftRecent = lhs.value.map(\.createdAt).max() ?? .distantPast
            let rightRecent = rhs.value.map(\.createdAt).max() ?? .distantPast
            if leftRecent != rightRecent { return leftRecent > rightRecent }
            if lhs.key.weekday != rhs.key.weekday { return lhs.key.weekday < rhs.key.weekday }
            if lhs.key.twoHourBlock != rhs.key.twoHourBlock { return lhs.key.twoHourBlock < rhs.key.twoHourBlock }
            return lhs.key.cue.rawValue < rhs.key.cue.rawValue
        }).first else { return nil }

        let minuteValues = winner.value.map { commitment in
            let components = calendar.dateComponents([.hour, .minute], from: commitment.createdAt)
            return (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }.sorted()
        let medianMinute = minuteValues[minuteValues.count / 2]
        let proactiveMinute = max(0, medianMinute - 10)

        return DistractionPattern(
            cue: winner.key.cue,
            weekday: winner.key.weekday,
            hour: proactiveMinute / 60,
            minute: proactiveMinute % 60,
            observations: winner.value.count
        )
    }
}
