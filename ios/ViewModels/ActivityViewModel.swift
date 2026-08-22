import Foundation

@MainActor
final class ActivityViewModel: ObservableObject {
    @Published var selectedDate = Date()
    @Published var selectedRange: ActivityDateRange = .all
    @Published var selectedFilter: ActivityEventKind = .all
    @Published private(set) var events: [MotionEvent] = []
    @Published private(set) var alerts: [AlertEvent] = []
    @Published private(set) var summaries: [DailyActivitySummary] = []
    @Published private(set) var trends: [TrendDay] = []
    @Published private(set) var state: LoadableState<[ActivityTimelineItem]> = .idle

    private let services: AppServiceContainer

    init(services: AppServiceContainer) {
        self.services = services
    }

    func load() async {
        state = .loading

        do {
            let device = try await services.deviceRepository.fetchDevice()
            async let loadedEvents = services.motionRepository.fetchMotionEvents(deviceID: device.id, date: selectedRange == .today ? selectedDate : nil)
            async let loadedSummaries = services.motionRepository.fetchDailySummaries(deviceID: device.id)
            async let loadedAlerts = services.alertRepository.fetchAlerts(deviceID: device.id)
            async let loadedTrends = services.motionRepository.fetchTrend(deviceID: device.id)
            events = eventsInSelectedRange(try await loadedEvents)
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
            .filter { selectedFilter == .all || $0.kind == selectedFilter }
            .sorted { $0.date > $1.date }
    }

    func applyFilter() {
        state = .loaded(timelineItems())
    }

    func datesForPicker() -> [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
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

    private func eventsInSelectedRange(_ loadedEvents: [MotionEvent]) -> [MotionEvent] {
        guard let cutoff = selectedRange.cutoffDate else {
            return loadedEvents
        }

        return loadedEvents.filter { $0.detectedAt >= cutoff }
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
