import Foundation
import SwiftUI

enum ConnectionStatus: String, Codable, Hashable {
    case online
    case offline
    case connecting

    var title: String {
        switch self {
        case .online: "Monitor Online"
        case .offline: "Monitor Offline"
        case .connecting: "Connecting"
        }
    }

    var tint: Color {
        switch self {
        case .online: .green
        case .offline: .orange
        case .connecting: .blue
        }
    }

    var symbol: String {
        switch self {
        case .online: "checkmark.circle.fill"
        case .offline: "exclamationmark.triangle.fill"
        case .connecting: "antenna.radiowaves.left.and.right"
        }
    }
}

enum WellnessState: String, Codable, Hashable {
    case normal
    case caution
    case critical
    case unknown

    var title: String {
        switch self {
        case .normal: "Everything looks normal"
        case .caution: "Longer than usual"
        case .critical: "Check on Grandma"
        case .unknown: "Activity unavailable"
        }
    }

    var subtitle: String {
        switch self {
        case .normal: "No unusual inactivity detected"
        case .caution: "Inactivity has passed the caution threshold"
        case .critical: "Inactivity has passed the critical threshold"
        case .unknown: "Motion activity may be incomplete"
        }
    }

    var tint: Color {
        switch self {
        case .normal: .green
        case .caution: .yellow
        case .critical: .red
        case .unknown: .secondary
        }
    }
}

enum BathroomMotionState: String, Codable, Hashable {
    case empty = "Bathroom empty"
    case motionDetected = "Motion detected"
    case monitorOffline = "Monitor offline"
}

enum ActivityEventKind: String, Codable, CaseIterable, Identifiable {
    case all = "All"
    case motion = "Motion"
    case caution = "Caution"
    case critical = "Critical"
    case deviceStatus = "Device Status"

    var id: String { rawValue }
}

struct MonitorDevice: Identifiable, Codable, Hashable {
    var id: String
    var displayName: String
    var serialNumber: String
    var roomName: String
    var monitoredPersonName: String
    var connectionStatus: ConnectionStatus
    var lastConnectedAt: Date
    var lastMotionAt: Date?
}

struct MotionEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let deviceID: String
    let detectedAt: Date
}

struct AlertEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let deviceID: String
    let kind: ActivityEventKind
    let occurredAt: Date
    let title: String
    let message: String
}

struct AlertPreferences: Codable, Hashable {
    var cautionThresholdHours: Int
    var criticalThresholdHours: Int
    var cautionAlertsEnabled: Bool
    var criticalAlertsEnabled: Bool
    var disconnectedAlertsEnabled: Bool
    var reconnectedAlertsEnabled: Bool

    static let defaults = AlertPreferences(
        cautionThresholdHours: 12,
        criticalThresholdHours: 24,
        cautionAlertsEnabled: true,
        criticalAlertsEnabled: true,
        disconnectedAlertsEnabled: true,
        reconnectedAlertsEnabled: true
    )

    var isValid: Bool {
        criticalThresholdHours > cautionThresholdHours
    }
}

struct NighttimeSchedule: Codable, Hashable {
    var startsAt: DateComponents
    var endsAt: DateComponents

    static let defaults = NighttimeSchedule(
        startsAt: DateComponents(hour: 22, minute: 0),
        endsAt: DateComponents(hour: 6, minute: 0)
    )
}

struct UserProfile: Codable, Hashable {
    var firstName: String
    var lastName: String
    var caregiverName: String
    var email: String
    var phone: String
}

struct AccountRegistration: Codable, Hashable {
    var firstName: String
    var lastName: String
    var email: String
    var phone: String
    var password: String
    var deviceID: String
    var monitoredPersonName: String
    var relationship: String?
    var monitorName: String
    var roomName: String
    var alertPreferences: AlertPreferences
    var notificationPreferences: AlertPreferences
    var nighttimeSchedule: NighttimeSchedule

    var displayName: String {
        [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct AccountProfile: Codable, Hashable {
    var firstName: String
    var lastName: String
    var email: String
    var phone: String

    var displayName: String {
        [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct CaregiverContact: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var relationship: String
    var phoneNumber: String
}

struct DailyActivitySummary: Identifiable, Codable, Hashable {
    var id: Date { date }
    let date: Date
    let visits: Int
    let currentInactivity: TimeInterval
    let longestInactivity: TimeInterval
    let comparison: String
    let currentBathroomState: BathroomMotionState
}

struct ActivityTimelineItem: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let kind: ActivityEventKind
    let title: String
    let detail: String
}

struct TrendDay: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let visits: Int
}

struct AppSnapshot: Hashable {
    var device: MonitorDevice
    var alertPreferences: AlertPreferences
    var nighttimeSchedule: NighttimeSchedule
    var profile: UserProfile
    var contacts: [CaregiverContact]
    var motionEvents: [MotionEvent]
    var alertEvents: [AlertEvent]
    var summaries: [DailyActivitySummary]
    var trends: [TrendDay]
}
