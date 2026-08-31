import Foundation

struct NotificationPreferences: Codable, Equatable, Sendable {
    struct TimeOfDay: Codable, Equatable, Sendable {
        var hour: Int
        var minute: Int
    }

    var isEnabled = true
    var morning = TimeOfDay(hour: 9, minute: 0)
    var afternoon = TimeOfDay(hour: 14, minute: 0)
    var evening = TimeOfDay(hour: 20, minute: 0)
    var enabledWeekdays: Set<Int> = Set(1...7)
    var quietHoursEnabled = false
    var quietHoursStart = TimeOfDay(hour: 22, minute: 0)
    var quietHoursEnd = TimeOfDay(hour: 7, minute: 0)
}
