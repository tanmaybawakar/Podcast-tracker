import Foundation

extension Date {
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

extension Double {
    var formattedTime: String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60
        let seconds = Int(self) % 60
        if hours > 0 { return String(format: "%dh %dm", hours, minutes) }
        if minutes > 0 { return String(format: "%dm %ds", minutes, seconds) }
        return String(format: "%ds", seconds)
    }
}
