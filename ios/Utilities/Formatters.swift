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

    static let fullDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
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

    static func daySectionTitle(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        return fullDay.string(from: date)
    }

    static func friendlyError(_ message: String) -> String {
        let lowered = message.lowercased()
        if lowered.contains("network") || lowered.contains("internet") || lowered.contains("connection") || lowered.contains("offline") {
            return "Could not connect. Check your internet and try again."
        }
        if lowered.contains("invalid login") || lowered.contains("invalid credentials") {
            return "That email or password did not match. Try again."
        }
        if lowered.contains("already registered") || lowered.contains("already exists") {
            return "An account already exists for that email. Sign in instead."
        }
        return message
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
