import Foundation

@MainActor
final class ActivityViewModel: ObservableObject {
    @Published var selectedDate = Date()
    @Published var selectedMode: ActivityDisplayMode = .day
    @Published private(set) var events: [MotionEvent] = []
    @Published private(set) var alerts: [AlertEvent] = []
    @Published private(set) var summaries: [DailyActivitySummary] = []
    @Published private(set) var trends: [TrendDay] = []
    @Published private(set) var deviceStatus: ConnectionStatus = .connecting
    @Published private(set) var pastDayMotionCount = 0
    @Published private(set) var currentInactivity: TimeInterval?
    @Published private(set) var longestInactivityPastDay: TimeInterval?
    @Published private(set) var activityComparison = "No activity has been recorded yet"
    @Published private(set) var state: LoadableState<[ActivityTimelineItem]> = .idle

    private let services: AppServiceContainer
    private var allEvents: [MotionEvent] = []
    private var allSessions: [MotionSession] = []

    init(services: AppServiceContainer) {
        self.services = services
    }

    func load() async {
        state = .loading

        do {
            let device = try await services.deviceRepository.fetchDevice()
            async let loadedEvents = services.motionRepository.fetchMotionEvents(deviceID: device.id, date: nil)
            async let loadedSessions = services.motionRepository.fetchMotionSessions(deviceID: device.id)
            async let loadedSummaries = services.motionRepository.fetchDailySummaries(deviceID: device.id)
            async let loadedAlerts = services.alertRepository.fetchAlerts(deviceID: device.id)
            async let loadedTrends = services.motionRepository.fetchTrend(deviceID: device.id)
            let allEvents = try await loadedEvents
            self.allEvents = allEvents
            allSessions = try await loadedSessions
            deviceStatus = device.connectionStatus
            updateOverview(from: allEvents)
            events = eventsForSelectedMode()
            summaries = try await loadedSummaries
            alerts = try await loadedAlerts
            trends = try await loadedTrends
            state = .loaded(timelineItems())
        } catch {
            state = .failed(Formatters.friendlyError(error.localizedDescription))
        }
    }

    func timelineItems() -> [ActivityTimelineItem] {
        var items = events.map {
            ActivityTimelineItem(
                date: $0.detectedAt,
                kind: .motion,
                title: "Motion detected",
                detail: inactivityGap(after: $0)
            )
        }

        items.append(contentsOf: alerts.map {
            ActivityTimelineItem(date: $0.occurredAt, kind: $0.kind, title: $0.title, detail: $0.message)
        })

        return items
            .sorted { $0.date > $1.date }
    }

    func applySelection() {
        events = eventsForSelectedMode()
        state = .loaded(timelineItems())
    }

    func dayRailDates() -> [Date] {
        (-2...2).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: selectedDate) }
    }

    func selectDay(_ date: Date) {
        selectedDate = date
        selectedMode = .day
        applySelection()
    }

    func moveSelectedDay(by dayOffset: Int) {
        selectedDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: selectedDate) ?? selectedDate
        selectedMode = .day
        applySelection()
    }

    func sessionsForSelectedDay() -> [ActivitySession] {
        sessions(on: selectedDate)
    }

    func groupedSessionsForSelectedDay() -> [(section: ActivityDaySection, sessions: [ActivitySession])] {
        let sessions = sessionsForSelectedDay()
        return ActivityDaySection.allCases.map { section in
            (section, sessions.filter { section.contains($0.startedAt) })
        }
    }

    func weekDays() -> [Date] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: selectedDate)
        return (0..<7)
            .compactMap { calendar.date(byAdding: .day, value: -6 + $0, to: end) }
    }

    func sessions(on date: Date) -> [ActivitySession] {
        let sessionRows = allSessions.filter { Calendar.current.isDate($0.startedAt, inSameDayAs: date) }
        if !sessionRows.isEmpty {
            return sessionRows
                .map { ActivitySession(motionSession: $0) }
                .sorted { $0.startedAt < $1.startedAt }
        }

        let calendar = Calendar.current
        let dayEvents = allEvents
            .filter { calendar.isDate($0.detectedAt, inSameDayAs: date) }
            .sorted { $0.detectedAt < $1.detectedAt }

        return Self.groupSessions(from: dayEvents)
    }

    func patternSummary() -> ActivityPatternSummary {
        let sessions = activitySessions()
        let groupedByDay = Dictionary(grouping: sessions) { Calendar.current.startOfDay(for: $0.startedAt) }
        let activeDays = groupedByDay.keys.count
        let averageVisits = activeDays == 0 ? 0 : Double(sessions.count) / Double(activeDays)
        let firstActivity = averageMinute(of: groupedByDay.values.compactMap { $0.min { $0.startedAt < $1.startedAt }?.startedAt })
        let lastActivity = averageMinute(of: groupedByDay.values.compactMap { $0.max { $0.startedAt < $1.startedAt }?.startedAt })
        let averageDuration = sessions.isEmpty ? nil : sessions.reduce(0) { $0 + $1.duration } / Double(sessions.count)
        let longerActivities = sessions.filter { $0.duration >= 20 * 60 }
        let mostActiveWeekday = weekdayWithMostSessions(from: sessions)
        let mostActiveSection = ActivityDaySection.allCases.max { left, right in
            sessions.filter { left.contains($0.startedAt) }.count < sessions.filter { right.contains($0.startedAt) }.count
        }

        return ActivityPatternSummary(
            averageVisitsPerDay: averageVisits,
            typicalFirstActivityMinute: firstActivity,
            typicalLastActivityMinute: lastActivity,
            averageSessionDuration: averageDuration,
            longerActivityRange: durationRange(for: longerActivities),
            mostActiveWeekday: mostActiveWeekday,
            mostActiveSection: mostActiveSection,
            activeDayCount: activeDays,
            totalSessionCount: sessions.count
        )
    }

    func recentPatternSessions(limit: Int = 6) -> [ActivitySession] {
        Array(activitySessions().sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }

    func weeklySessionCount() -> Int {
        weekDays().reduce(0) { $0 + sessions(on: $1).count }
    }

    func mostActiveWeekday() -> (date: Date, count: Int)? {
        weekDays()
            .map { ($0, sessions(on: $0).count) }
            .max { $0.1 < $1.1 }
    }

    func longestQuietGapForWeek() -> TimeInterval? {
        let weekEvents = weekDays()
            .flatMap { date in allEvents.filter { Calendar.current.isDate($0.detectedAt, inSameDayAs: date) } }
            .sorted { $0.detectedAt < $1.detectedAt }
        return Self.longestGap(in: weekEvents, fallback: nil)
    }

    func groupedTimelineItems(_ items: [ActivityTimelineItem]) -> [(title: String, items: [ActivityTimelineItem])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.date)
        }

        return grouped
            .sorted { $0.key > $1.key }
            .map { (title: Formatters.daySectionTitle($0.key), items: $0.value.sorted { $0.date > $1.date }) }
    }

    private func eventsForSelectedMode() -> [MotionEvent] {
        switch selectedMode {
        case .patterns:
            return allEvents
        case .day:
            return allEvents.filter { Calendar.current.isDate($0.detectedAt, inSameDayAs: selectedDate) }
        case .week:
            guard let firstDay = weekDays().first,
                  let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: selectedDate)) else {
                return allEvents
            }
            return allEvents.filter { $0.detectedAt >= firstDay && $0.detectedAt < end }
        }
    }

    private func activitySessions() -> [ActivitySession] {
        if !allSessions.isEmpty {
            return allSessions.map { ActivitySession(motionSession: $0) }
                .sorted { $0.startedAt < $1.startedAt }
        }

        let grouped = Dictionary(grouping: allEvents) { Calendar.current.startOfDay(for: $0.detectedAt) }
        return grouped.values
            .flatMap { Self.groupSessions(from: $0.sorted { $0.detectedAt < $1.detectedAt }) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    private func averageMinute(of dates: [Date]) -> Int? {
        guard !dates.isEmpty else { return nil }
        let total = dates.reduce(0) { partial, date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            return partial + (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }
        return total / dates.count
    }

    private func durationRange(for sessions: [ActivitySession]) -> ClosedRange<TimeInterval>? {
        guard let min = sessions.map(\.duration).min(),
              let max = sessions.map(\.duration).max() else {
            return nil
        }
        return min...max
    }

    private func weekdayWithMostSessions(from sessions: [ActivitySession]) -> String? {
        let grouped = Dictionary(grouping: sessions) {
            Calendar.current.component(.weekday, from: $0.startedAt)
        }
        guard let weekday = grouped.max(by: { $0.value.count < $1.value.count })?.key else {
            return nil
        }
        return Calendar.current.weekdaySymbols[weekday - 1]
    }

    private static func groupSessions(from events: [MotionEvent]) -> [ActivitySession] {
        guard var currentStart = events.first?.detectedAt else {
            return []
        }

        let sessionGap: TimeInterval = 5 * 60
        var currentEnd = currentStart
        var motionCount = 0
        var sessions: [ActivitySession] = []

        for event in events {
            if event.detectedAt.timeIntervalSince(currentEnd) > sessionGap {
                sessions.append(ActivitySession(startedAt: currentStart, endedAt: currentEnd, motionCount: motionCount))
                currentStart = event.detectedAt
                motionCount = 0
            }

            currentEnd = event.detectedAt
            motionCount += 1
        }

        sessions.append(ActivitySession(startedAt: currentStart, endedAt: currentEnd, motionCount: motionCount))
        return sessions.sorted { $0.startedAt < $1.startedAt }
    }

    private func eventsInSelectedRange(_ loadedEvents: [MotionEvent]) -> [MotionEvent] {
        guard let cutoff = ActivityDateRange.today.cutoffDate else {
            return loadedEvents
        }

        return loadedEvents.filter { $0.detectedAt >= cutoff }
    }

    private func updateOverview(from loadedEvents: [MotionEvent]) {
        let sorted = loadedEvents.sorted { $0.detectedAt < $1.detectedAt }
        let now = Date()
        let dayAgo = now.addingTimeInterval(-24 * 60 * 60)
        let pastDayEvents = sorted.filter { $0.detectedAt >= dayAgo }

        pastDayMotionCount = pastDayEvents.count
        currentInactivity = sorted.last.map { now.timeIntervalSince($0.detectedAt) }
        longestInactivityPastDay = Self.longestGap(in: pastDayEvents, fallback: currentInactivity)

        if let lastMotion = sorted.last {
            activityComparison = "Last motion \(Formatters.relative(lastMotion.detectedAt))"
        } else {
            activityComparison = "No activity has been recorded yet"
        }
    }

    private static func longestGap(in events: [MotionEvent], fallback: TimeInterval?) -> TimeInterval? {
        guard !events.isEmpty else { return fallback }
        let longestGap = zip(events, events.dropFirst())
            .map { $1.detectedAt.timeIntervalSince($0.detectedAt) }
            .max() ?? 0
        return max(longestGap, 0)
    }

    private func inactivityGap(after event: MotionEvent) -> String {
        guard let next = events.first(where: { $0.detectedAt < event.detectedAt }) else {
            return "\(Formatters.relative(event.detectedAt))"
        }
        return "\(Formatters.duration(event.detectedAt.timeIntervalSince(next.detectedAt))) without detected motion"
    }
}

enum ActivityDateRange: String, CaseIterable, Identifiable {
    case all = "All"
    case today = "Today"
    case sevenDays = "7 days"
    case thirtyDays = "30 days"

    var id: String { rawValue }

    var dayCount: Int {
        switch self {
        case .all: 0
        case .today: 1
        case .sevenDays: 7
        case .thirtyDays: 30
        }
    }

    var cutoffDate: Date? {
        switch self {
        case .all:
            return nil
        case .today:
            return Calendar.current.startOfDay(for: Date())
        case .sevenDays, .thirtyDays:
            return Calendar.current.date(
                byAdding: .day,
                value: -(dayCount - 1),
                to: Calendar.current.startOfDay(for: Date())
            )
        }
    }
}

enum ActivityDisplayMode: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case patterns = "Patterns"

    var id: String { rawValue }
}

struct ActivitySession: Identifiable, Hashable {
    let id = UUID()
    let startedAt: Date
    let endedAt: Date
    let motionCount: Int

    init(startedAt: Date, endedAt: Date, motionCount: Int) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.motionCount = motionCount
    }

    init(motionSession: MotionSession) {
        startedAt = motionSession.startedAt
        endedAt = motionSession.endedAt ?? motionSession.startedAt
        motionCount = motionSession.motionCount
    }

    var duration: TimeInterval {
        max(endedAt.timeIntervalSince(startedAt), 60)
    }

    var label: String {
        if duration >= 20 * 60 {
            return "Longer activity"
        }
        if duration <= 5 * 60 {
            return "Quick visit"
        }
        return "Routine activity"
    }
}

struct ActivityPatternSummary {
    let averageVisitsPerDay: Double
    let typicalFirstActivityMinute: Int?
    let typicalLastActivityMinute: Int?
    let averageSessionDuration: TimeInterval?
    let longerActivityRange: ClosedRange<TimeInterval>?
    let mostActiveWeekday: String?
    let mostActiveSection: ActivityDaySection?
    let activeDayCount: Int
    let totalSessionCount: Int
}

enum ActivityDaySection: String, CaseIterable, Identifiable {
    case morning = "Morning"
    case afternoon = "Afternoon"
    case evening = "Evening"
    case night = "Night"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .morning: "sunrise"
        case .afternoon: "sun.max"
        case .evening: "sunset"
        case .night: "moon"
        }
    }

    func contains(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        switch self {
        case .morning:
            return (6..<12).contains(hour)
        case .afternoon:
            return (12..<18).contains(hour)
        case .evening:
            return (18..<24).contains(hour)
        case .night:
            return (0..<6).contains(hour)
        }
    }
}
