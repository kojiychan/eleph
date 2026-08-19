import Foundation

enum Formatters {
    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    static func relative(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "No activity recorded" }
        return relative.localizedString(for: date, relativeTo: now)
    }

    static func exactTime(_ date: Date?) -> String {
        guard let date else { return "Not available" }
        return time.string(from: date)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(Int(interval / 60), 0)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours == 0 {
            return "\(remainingMinutes)m"
        }
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
    }

    static func connectionDuration(since date: Date, now: Date = Date()) -> String {
        let phrase = relative.localizedString(for: date, relativeTo: now)
        return phrase.replacingOccurrences(of: " ago", with: "")
    }

    static func time(from components: DateComponents) -> String {
        let date = Calendar.current.date(from: components) ?? Date()
        return time.string(from: date)
    }
}
