import Foundation
import Supabase

actor SupabaseAppRepository: DeviceRepository, MotionEventRepository, AlertRepository {
    private let client: SupabaseClient
    private let identityStore: DeviceIdentityStore
    private let fallbackDeviceID: String
    private let preferencesStore = UserDefaultsAlertPreferencesStore()

    init(configuration: AppConfiguration, identityStore: DeviceIdentityStore) {
        self.client = SupabaseClient(
            supabaseURL: configuration.supabaseURL,
            supabaseKey: configuration.supabaseAnonKey
        )
        self.identityStore = identityStore
        self.fallbackDeviceID = configuration.monitorDeviceID

        if identityStore.loadDeviceID() == nil {
            identityStore.saveDeviceID(configuration.monitorDeviceID)
        }
    }

    func fetchDevice() async throws -> MonitorDevice {
        let deviceID = identityStore.loadDeviceID() ?? fallbackDeviceID

        do {
            let rows: [SupabaseDeviceRow] = try await client
                .from("devices")
                .select()
                .eq("device_id", value: deviceID)
                .limit(1)
                .execute()
                .value

            if let row = rows.first {
                return row.toMonitorDevice(fallbackID: deviceID)
            }
        } catch {
            // The current backend may only have motion_events. Keep the app usable until devices exists.
        }

        let latest = try? await fetchMotionEvents(deviceID: deviceID, date: nil).first
        return MonitorDevice(
            id: deviceID,
            displayName: "Grandma's Bathroom",
            serialNumber: deviceID,
            roomName: "Hall Bathroom",
            monitoredPersonName: "Grandma",
            connectionStatus: .online,
            lastConnectedAt: Date(),
            lastMotionAt: latest?.detectedAt
        )
    }

    func saveDevice(_ device: MonitorDevice) async throws {
        identityStore.saveDeviceID(device.id)
    }

    func fetchMotionEvents(deviceID: String, date: Date?) async throws -> [MotionEvent] {
        let query = client
            .from("motion_events")
            .select()
            .eq("device_id", value: deviceID)
            .order("detected_at", ascending: false)
            .limit(date == nil ? 250 : 1_000)

        let rows: [SupabaseMotionEventRow] = try await query.execute().value
        let events = rows.map { $0.toMotionEvent() }

        guard let date else {
            return events
        }

        return events.filter {
            Calendar.current.isDate($0.detectedAt, inSameDayAs: date)
        }
    }

    func fetchDailySummaries(deviceID: String) async throws -> [DailyActivitySummary] {
        let events = try await fetchMotionEvents(deviceID: deviceID, date: nil)
        return (0..<7).compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else {
                return nil
            }
            let dayEvents = events.filter { Calendar.current.isDate($0.detectedAt, inSameDayAs: date) }
            return Self.summary(for: date, events: dayEvents)
        }
    }

    func fetchTrend(deviceID: String) async throws -> [TrendDay] {
        let summaries = try await fetchDailySummaries(deviceID: deviceID)
        return summaries
            .sorted { $0.date < $1.date }
            .map { TrendDay(date: $0.date, visits: $0.visits) }
    }

    func fetchAlerts(deviceID: String) async throws -> [AlertEvent] {
        []
    }

    func fetchPreferences() async throws -> AlertPreferences {
        preferencesStore.load()
    }

    func savePreferences(_ preferences: AlertPreferences) async throws {
        guard preferences.isValid else {
            throw AppServiceError.validation("Critical alert must be later than caution alert.")
        }
        preferencesStore.save(preferences)
    }

    private static func summary(for date: Date, events: [MotionEvent]) -> DailyActivitySummary {
        let sorted = events.sorted { $0.detectedAt < $1.detectedAt }
        let now = Date()
        let latest = sorted.last?.detectedAt
        let currentInactivity = latest.map { now.timeIntervalSince($0) } ?? 0

        let longestGap = zip(sorted, sorted.dropFirst())
            .map { $1.detectedAt.timeIntervalSince($0.detectedAt) }
            .max() ?? currentInactivity

        let state: BathroomMotionState
        if let latest, now.timeIntervalSince(latest) < 5 * 60 {
            state = .motionDetected
        } else {
            state = .empty
        }

        return DailyActivitySummary(
            date: date,
            visits: sorted.count,
            currentInactivity: Calendar.current.isDateInToday(date) ? currentInactivity : 0,
            longestInactivity: max(longestGap, 0),
            comparison: sorted.isEmpty ? "No activity has been recorded yet" : "Activity is based on recorded motion events",
            currentBathroomState: state
        )
    }
}

private struct SupabaseMotionEventRow: Decodable {
    let id: UUID
    let deviceID: String
    let detectedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case deviceID = "device_id"
        case detectedAt = "detected_at"
    }

    func toMotionEvent() -> MotionEvent {
        MotionEvent(id: id, deviceID: deviceID, detectedAt: detectedAt)
    }
}

private struct SupabaseDeviceRow: Decodable {
    let deviceID: String?
    let id: String?
    let displayName: String?
    let name: String?
    let serialNumber: String?
    let roomName: String?
    let location: String?
    let monitoredPersonName: String?
    let connectionStatus: String?
    let isOnline: Bool?
    let lastConnectedAt: Date?
    let lastSeenAt: Date?
    let lastMotionAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case deviceID = "device_id"
        case displayName = "display_name"
        case name
        case serialNumber = "serial_number"
        case roomName = "room_name"
        case location
        case monitoredPersonName = "monitored_person_name"
        case connectionStatus = "connection_status"
        case isOnline = "is_online"
        case lastConnectedAt = "last_connected_at"
        case lastSeenAt = "last_seen_at"
        case lastMotionAt = "last_motion_at"
    }

    func toMonitorDevice(fallbackID: String) -> MonitorDevice {
        let resolvedID = deviceID ?? id ?? fallbackID
        return MonitorDevice(
            id: resolvedID,
            displayName: displayName ?? name ?? "Grandma's Bathroom",
            serialNumber: serialNumber ?? resolvedID,
            roomName: roomName ?? location ?? "Hall Bathroom",
            monitoredPersonName: monitoredPersonName ?? "Grandma",
            connectionStatus: resolvedStatus,
            lastConnectedAt: lastConnectedAt ?? lastSeenAt ?? Date(),
            lastMotionAt: lastMotionAt
        )
    }

    private var resolvedStatus: ConnectionStatus {
        if let connectionStatus,
           let status = ConnectionStatus(rawValue: connectionStatus.lowercased()) {
            return status
        }
        if let isOnline {
            return isOnline ? .online : .offline
        }
        return .online
    }
}

private final class UserDefaultsAlertPreferencesStore {
    private let key = "eleph.alertPreferences"
    private let defaults = UserDefaults.standard

    func load() -> AlertPreferences {
        guard let data = defaults.data(forKey: key),
              let preferences = try? JSONDecoder().decode(AlertPreferences.self, from: data) else {
            return .defaults
        }
        return preferences
    }

    func save(_ preferences: AlertPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
