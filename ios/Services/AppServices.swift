import Foundation

protocol DeviceRepository {
    func fetchDevice() async throws -> MonitorDevice
    func saveDevice(_ device: MonitorDevice) async throws
}

protocol MotionEventRepository {
    func fetchMotionEvents(deviceID: String, date: Date?) async throws -> [MotionEvent]
    func fetchMotionSessions(deviceID: String) async throws -> [MotionSession]
    func fetchDailySummaries(deviceID: String) async throws -> [DailyActivitySummary]
    func fetchTrend(deviceID: String) async throws -> [TrendDay]
}

protocol AlertRepository {
    func fetchAlerts(deviceID: String) async throws -> [AlertEvent]
    func fetchPreferences() async throws -> AlertPreferences
    func savePreferences(_ preferences: AlertPreferences) async throws
}

protocol AuthenticationService {
    func signInWithApple() async throws
    func signInWithGoogle() async throws
    func continueWithEmail(_ email: String) async throws
    func signIn(email: String, password: String) async throws
    func createAccount(_ registration: AccountRegistration) async throws
    func handleAuthCallback(_ url: URL) async throws
    func loadProfile() async throws -> AccountProfile
    func saveProfile(_ profile: AccountProfile) async throws
    func hasActiveSession() async -> Bool
    func signOut() async throws
}

struct AccountVerificationRequired: LocalizedError {
    let email: String

    var errorDescription: String? {
        "Check your email to verify your account."
    }
}

protocol BluetoothProvisioningService {
    func discoverMonitor() async throws -> MonitorDevice
    func connect(to device: MonitorDevice) async throws -> MonitorDevice
    func waitForMotionTest(deviceID: String) async throws -> Bool
}

protocol WiFiProvisioningService {
    func connect(deviceID: String, networkName: String, password: String) async throws
}

protocol DeviceIdentityStore {
    func loadDeviceID() -> String?
    func saveDeviceID(_ id: String)
    func hasCompletedOnboarding() -> Bool
    func setOnboardingCompleted(_ completed: Bool)
}

struct AppServiceContainer {
    let deviceRepository: DeviceRepository
    let motionRepository: MotionEventRepository
    let alertRepository: AlertRepository
    let authenticationService: AuthenticationService
    let bluetoothService: BluetoothProvisioningService
    let wifiService: WiFiProvisioningService
    let identityStore: DeviceIdentityStore
    let isUsingMockData: Bool
    let betaMonitorDeviceID: String
    let legalLinks: LegalLinks

    static func liveOrMock() -> AppServiceContainer {
        let store = UserDefaultsDeviceIdentityStore()
        guard let configuration = AppConfiguration.load() else {
            #if DEBUG
            return mock()
            #else
            fatalError("Supabase configuration is required for TestFlight and release builds.")
            #endif
        }

        let repository = SupabaseAppRepository(configuration: configuration, identityStore: store)
        return AppServiceContainer(
            deviceRepository: repository,
            motionRepository: repository,
            alertRepository: repository,
            authenticationService: SupabaseAuthenticationService(configuration: configuration, identityStore: store),
            bluetoothService: MockBluetoothProvisioningService(),
            wifiService: MockWiFiProvisioningService(),
            identityStore: store,
            isUsingMockData: false,
            betaMonitorDeviceID: configuration.monitorDeviceID,
            legalLinks: configuration.legalLinks
        )
    }

    static func mock(scenario: PreviewScenario = .normalOnline) -> AppServiceContainer {
        let store = UserDefaultsDeviceIdentityStore(suiteName: "ElephMock-\(scenario.rawValue)")
        let data = MockData.snapshot(for: scenario)
        let repository = MockAppRepository(snapshot: data, identityStore: store)

        return AppServiceContainer(
            deviceRepository: repository,
            motionRepository: repository,
            alertRepository: repository,
            authenticationService: MockAuthenticationService(),
            bluetoothService: MockBluetoothProvisioningService(),
            wifiService: MockWiFiProvisioningService(),
            identityStore: store,
            isUsingMockData: true,
            betaMonitorDeviceID: data.device.id,
            legalLinks: .betaDefaults
        )
    }
}
