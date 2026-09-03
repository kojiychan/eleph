import Foundation

final class UserDefaultsDeviceIdentityStore: DeviceIdentityStore {
    private let defaults: UserDefaults
    private let deviceIDKey = "eleph.deviceID"
    private let onboardingKey = "eleph.onboardingCompleted"

    init(suiteName: String? = nil) {
        if let suiteName, let defaults = UserDefaults(suiteName: suiteName) {
            self.defaults = defaults
        } else {
            self.defaults = .standard
        }
    }

    func loadDeviceID() -> String? {
        defaults.string(forKey: deviceIDKey)
    }

    func saveDeviceID(_ id: String) {
        defaults.set(id, forKey: deviceIDKey)
    }

    func hasCompletedOnboarding() -> Bool {
        defaults.bool(forKey: onboardingKey)
    }

    func setOnboardingCompleted(_ completed: Bool) {
        defaults.set(completed, forKey: onboardingKey)
    }
}

actor MockAppRepository: DeviceRepository, MotionEventRepository, AlertRepository {
    private var snapshot: AppSnapshot
    private let identityStore: DeviceIdentityStore

    init(snapshot: AppSnapshot, identityStore: DeviceIdentityStore) {
        self.snapshot = snapshot
        self.identityStore = identityStore
        if identityStore.loadDeviceID() == nil {
            identityStore.saveDeviceID(snapshot.device.id)
        }
    }

    func fetchDevice() async throws -> MonitorDevice {
        try await Task.sleep(for: .milliseconds(180))
        return snapshot.device
    }

    func saveDevice(_ device: MonitorDevice) async throws {
        snapshot.device = device
        identityStore.saveDeviceID(device.id)
    }

    func fetchMotionEvents(deviceID: String, date: Date?) async throws -> [MotionEvent] {
        try await Task.sleep(for: .milliseconds(180))
        guard let date else {
            return snapshot.motionEvents
        }

        return snapshot.motionEvents.filter {
            Calendar.current.isDate($0.detectedAt, inSameDayAs: date)
        }
    }

    func fetchMotionSessions(deviceID: String) async throws -> [MotionSession] {
        try await Task.sleep(for: .milliseconds(120))
        return []
    }

    func fetchDailySummaries(deviceID: String) async throws -> [DailyActivitySummary] {
        try await Task.sleep(for: .milliseconds(120))
        return snapshot.summaries
    }

    func fetchTrend(deviceID: String) async throws -> [TrendDay] {
        try await Task.sleep(for: .milliseconds(120))
        return snapshot.trends
    }

    func fetchAlerts(deviceID: String) async throws -> [AlertEvent] {
        try await Task.sleep(for: .milliseconds(120))
        return snapshot.alertEvents
    }

    func fetchPreferences() async throws -> AlertPreferences {
        snapshot.alertPreferences
    }

    func savePreferences(_ preferences: AlertPreferences) async throws {
        guard preferences.isValid else {
            throw AppServiceError.validation("Critical alert must be later than caution alert.")
        }
        snapshot.alertPreferences = preferences
    }
}

struct MockAuthenticationService: AuthenticationService {
    func signInWithApple() async throws { try await Task.sleep(for: .milliseconds(400)) }
    func signInWithGoogle() async throws { try await Task.sleep(for: .milliseconds(400)) }
    func continueWithEmail(_ email: String) async throws { try await Task.sleep(for: .milliseconds(400)) }
    func signIn(email: String, password: String) async throws { try await Task.sleep(for: .milliseconds(400)) }
    func createAccount(_ registration: AccountRegistration) async throws { try await Task.sleep(for: .milliseconds(500)) }
    func handleAuthCallback(_ url: URL) async throws { try await Task.sleep(for: .milliseconds(200)) }
    func loadProfile() async throws -> AccountProfile {
        AccountProfile(firstName: "Koji", lastName: "", email: "koji@example.com", phone: "(555) 010-0000")
    }
    func saveProfile(_ profile: AccountProfile) async throws { try await Task.sleep(for: .milliseconds(300)) }
    func hasActiveSession() async -> Bool { true }
    func signOut() async throws { try await Task.sleep(for: .milliseconds(200)) }
}

struct MockBluetoothProvisioningService: BluetoothProvisioningService {
    func discoverMonitor() async throws -> MonitorDevice {
        try await Task.sleep(for: .milliseconds(700))
        return MockData.stableDevice(connectionStatus: .connecting)
    }

    func connect(to device: MonitorDevice) async throws -> MonitorDevice {
        try await Task.sleep(for: .milliseconds(700))
        var connected = device
        connected.connectionStatus = .online
        connected.lastConnectedAt = Date()
        return connected
    }

    func waitForMotionTest(deviceID: String) async throws -> Bool {
        try await Task.sleep(for: .seconds(1))
        return true
    }
}

struct MockWiFiProvisioningService: WiFiProvisioningService {
    func connect(deviceID: String, networkName: String, password: String) async throws {
        try await Task.sleep(for: .seconds(1))
    }
}

struct MockElephSetupBluetoothService: ElephSetupBluetoothService {
    var shouldFailScan = false
    var shouldFailConnection = false
    var shouldFailProvisioning = false

    func scanForSetupDevices() async throws -> [SetupDevice] {
        try await Task.sleep(for: .milliseconds(700))
        if shouldFailScan {
            throw AppServiceError.validation("No nearby Eleph monitors were found.")
        }

        return [
            SetupDevice(
                name: "Eleph Monitor",
                advertisedName: "Eleph Setup",
                signalStrength: -42,
                serviceUUID: "E1E10001-4B18-4F7D-9D25-ELEPHSETUP01"
            )
        ]
    }

    func connect(to setupDevice: SetupDevice) async throws {
        try await Task.sleep(for: .milliseconds(600))
        if shouldFailConnection {
            throw AppServiceError.validation("Could not connect to \(setupDevice.name).")
        }
    }

    func readSetupStatus() async throws -> SetupStatus {
        try await Task.sleep(for: .milliseconds(250))
        return .readyForProvisioning
    }

    func sendProvisioningPayload(_ payload: ProvisioningPayload) async throws {
        try await Task.sleep(for: .milliseconds(900))
        if shouldFailProvisioning {
            throw AppServiceError.validation("The monitor could not accept Wi-Fi setup.")
        }
    }

    func observeProvisioningStatus() async throws -> ProvisioningStatus {
        try await Task.sleep(for: .milliseconds(600))
        return shouldFailProvisioning ? .failed : .online
    }
}

struct MockDevicePairingService: DevicePairingService {
    let identityStore: DeviceIdentityStore
    var shouldFail = false

    func claimDevice(deviceID: String, claimToken: String, displayName: String) async throws {
        try await Task.sleep(for: .milliseconds(500))
        if shouldFail {
            throw AppServiceError.validation("This device could not be paired to your account.")
        }
        identityStore.saveDeviceID(deviceID)
    }
}

struct MockDeviceHeartbeatService: DeviceHeartbeatService {
    var shouldTimeout = false

    func waitForDeviceOnline(deviceID: String, timeoutSeconds: Int) async throws {
        try await Task.sleep(for: .seconds(1))
        if shouldTimeout {
            throw AppServiceError.validation("Timed out waiting for the monitor to come online.")
        }
    }
}

enum AppServiceError: LocalizedError {
    case validation(String)

    var errorDescription: String? {
        switch self {
        case .validation(let message): message
        }
    }
}
