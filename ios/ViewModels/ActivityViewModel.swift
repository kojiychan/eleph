import Foundation

@MainActor
final class ActivityViewModel: ObservableObject {
    @Published var selectedDate = Date()
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
            async let loadedEvents = services.motionRepository.fetchMotionEvents(deviceID: device.id, date: selectedDate)
            async let loadedSummaries = services.motionRepository.fetchDailySummaries(deviceID: device.id)
            async let loadedAlerts = services.alertRepository.fetchAlerts(deviceID: device.id)
            async let loadedTrends = services.motionRepository.fetchTrend(deviceID: device.id)
            events = try await loadedEvents
            summaries = try await loadedSummaries
            alerts = try await loadedAlerts
            trends = try await loadedTrends
            state = .loaded(timelineItems())
        } catch {
            state = .failed(error.localizedDescription)
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

    private func inactivityGap(after event: MotionEvent) -> String {
        guard let next = events.first(where: { $0.detectedAt < event.detectedAt }) else {
            return "\(Formatters.relative(event.detectedAt))"
        }
        return "\(Formatters.duration(event.detectedAt.timeIntervalSince(next.detectedAt))) without detected motion"
    }
}
