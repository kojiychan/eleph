import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var state: LoadableState<AppSnapshot> = .idle

    private let services: AppServiceContainer

    init(services: AppServiceContainer) {
        self.services = services
    }

    func load() async {
        state = .loading

        do {
            let device = try await services.deviceRepository.fetchDevice()
            async let events = services.motionRepository.fetchMotionEvents(deviceID: device.id, date: nil)
            async let summaries = services.motionRepository.fetchDailySummaries(deviceID: device.id)
            async let trends = services.motionRepository.fetchTrend(deviceID: device.id)
            async let alerts = services.alertRepository.fetchAlerts(deviceID: device.id)
            async let preferences = services.alertRepository.fetchPreferences()

            let snapshot = AppSnapshot(
                device: device,
                alertPreferences: try await preferences,
                nighttimeSchedule: .defaults,
                profile: UserProfile(caregiverName: "Koji", email: "koji@example.com"),
                contacts: [],
                motionEvents: try await events,
                alertEvents: try await alerts,
                summaries: try await summaries,
                trends: try await trends
            )
            state = .loaded(snapshot)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func wellnessState(for snapshot: AppSnapshot) -> WellnessState {
        guard snapshot.device.connectionStatus == .online else {
            return .unknown
        }
        let inactivity = snapshot.summaries.first?.currentInactivity ?? inactivitySinceLastMotion(snapshot.device)
        let caution = Double(snapshot.alertPreferences.cautionThresholdHours) * 3600
        let critical = Double(snapshot.alertPreferences.criticalThresholdHours) * 3600

        if inactivity >= critical { return .critical }
        if inactivity >= caution { return .caution }
        return .normal
    }

    func inactivitySinceLastMotion(_ device: MonitorDevice) -> TimeInterval {
        guard let lastMotionAt = device.lastMotionAt else { return 0 }
        return Date().timeIntervalSince(lastMotionAt)
    }
}
