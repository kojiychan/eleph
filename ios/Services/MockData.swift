import Foundation

enum MockData {
    static func stableDevice(id: String = "bathroom-monitor-001", connectionStatus: ConnectionStatus = .online) -> MonitorDevice {
        MonitorDevice(
            id: id,
            displayName: "Grandma's Bathroom",
            serialNumber: "ELEPH-001-8F3A",
            roomName: "Hall Bathroom",
            monitoredPersonName: "Grandma",
            connectionStatus: connectionStatus,
            lastConnectedAt: Date().addingTimeInterval(connectionStatus == .online ? -60 : -18 * 60),
            lastMotionAt: Date().addingTimeInterval(-42 * 60)
        )
    }

    static func snapshot(for scenario: PreviewScenario) -> AppSnapshot {
        let now = Date()
        var device = stableDevice()
        var events = motionEvents(now: now)
        var summaries = dailySummaries(now: now, visits: 9, inactivity: 42 * 60, longest: 3 * 3600)
        var alerts: [AlertEvent] = []

        switch scenario {
        case .normalOnline, .onboardingComplete:
            break
        case .cautionInactivity:
            device.lastMotionAt = now.addingTimeInterval(-13 * 3600)
            summaries = dailySummaries(now: now, visits: 3, inactivity: 13 * 3600, longest: 13 * 3600, comparison: "Activity is lower than recent days")
            alerts = [alert(kind: .caution, hoursAgo: 1, title: "Caution inactivity alert")]
        case .criticalInactivity:
            device.lastMotionAt = now.addingTimeInterval(-25 * 3600)
            summaries = dailySummaries(now: now, visits: 1, inactivity: 25 * 3600, longest: 25 * 3600, comparison: "Activity is lower than recent days")
            alerts = [alert(kind: .critical, hoursAgo: 1, title: "Critical inactivity alert")]
        case .recentlyDisconnected:
            device.connectionStatus = .offline
            device.lastConnectedAt = now.addingTimeInterval(-18 * 60)
            alerts = [alert(kind: .deviceStatus, hoursAgo: 0.3, title: "Monitor disconnected")]
        case .offlineSeveralHours:
            device.connectionStatus = .offline
            device.lastConnectedAt = now.addingTimeInterval(-4 * 3600)
            device.lastMotionAt = now.addingTimeInterval(-5 * 3600)
            alerts = [alert(kind: .deviceStatus, hoursAgo: 4, title: "Monitor disconnected")]
        case .noActivity:
            device.lastMotionAt = nil
            events = []
            summaries = dailySummaries(now: now, visits: 0, inactivity: 0, longest: 0, state: .empty, comparison: "No activity has been recorded yet")
        case .onboardingIncomplete:
            device.connectionStatus = .offline
            device.lastMotionAt = nil
            events = []
        }

        return AppSnapshot(
            device: device,
            alertPreferences: .defaults,
            nighttimeSchedule: .defaults,
            profile: UserProfile(firstName: "Koji", lastName: "", caregiverName: "Koji", email: "koji@example.com", phone: "555-0100"),
            contacts: [
                CaregiverContact(id: UUID(), name: "Maya", relationship: "Daughter", phoneNumber: "(555) 010-1234"),
                CaregiverContact(id: UUID(), name: "Dr. Lee", relationship: "Clinician", phoneNumber: "(555) 010-9876")
            ],
            motionEvents: events,
            alertEvents: alerts,
            summaries: summaries,
            trends: trend(now: now)
        )
    }

    static func motionEvents(now: Date) -> [MotionEvent] {
        [42, 96, 164, 312, 434, 612, 780, 1_020, 1_260].map {
            MotionEvent(id: UUID(), deviceID: "bathroom-monitor-001", detectedAt: now.addingTimeInterval(-Double($0 * 60)))
        }
    }

    static func dailySummaries(
        now: Date,
        visits: Int,
        inactivity: TimeInterval,
        longest: TimeInterval,
        state: BathroomMotionState = .empty,
        comparison: String = "Activity is within the usual range"
    ) -> [DailyActivitySummary] {
        (0..<7).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: now) ?? now
            return DailyActivitySummary(
                date: date,
                visits: max(visits - offset % 3, 0),
                currentInactivity: offset == 0 ? inactivity : 0,
                longestInactivity: longest + Double(offset % 2) * 1800,
                comparison: offset == 0 ? comparison : "Activity was within the usual range",
                currentBathroomState: offset == 0 ? state : .empty
            )
        }
    }

    static func trend(now: Date) -> [TrendDay] {
        [8, 10, 7, 9, 11, 8, 9].enumerated().map { index, visits in
            let day = Calendar.current.date(byAdding: .day, value: index - 6, to: now) ?? now
            return TrendDay(date: day, visits: visits)
        }
    }

    private static func alert(kind: ActivityEventKind, hoursAgo: Double, title: String) -> AlertEvent {
        AlertEvent(
            id: UUID(),
            deviceID: "bathroom-monitor-001",
            kind: kind,
            occurredAt: Date().addingTimeInterval(-hoursAgo * 3600),
            title: title,
            message: "Motion activity may need attention."
        )
    }
}
