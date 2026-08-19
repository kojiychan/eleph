import Foundation

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var step: OnboardingStep = .welcome
    @Published var discoveredDevice: MonitorDevice?
    @Published var bluetoothState: ProvisioningState = .idle
    @Published var wifiState: ProvisioningState = .idle
    @Published var motionTestState: MotionTestState = .waiting
    @Published var networkName = "Koji Home"
    @Published var wifiPassword = ""
    @Published var selectedPersonOption: MonitoredPersonOption = .grandma
    @Published var customPersonName = ""
    @Published var personName = "Grandma"
    @Published var monitorName = "Grandma's Bathroom"
    @Published var roomName = "Hall Bathroom"
    @Published var alertPreferences = AlertPreferences.defaults
    @Published var nighttimeSchedule = NighttimeSchedule.defaults
    @Published var notifications = AlertPreferences.defaults
    @Published var caregiverName = "Koji"
    @Published var accountEmail = ""
    @Published var accountPhone = ""
    @Published var accountPassword = ""
    @Published var accountConfirmPassword = ""
    @Published var loginEmail = ""
    @Published var loginPassword = ""
    @Published var completedPlacementItems: Set<PlacementChecklistItem> = []
    @Published var errorMessage: String?

    private let services: AppServiceContainer

    init(services: AppServiceContainer) {
        self.services = services
    }

    var totalSteps: Int {
        OnboardingStep.progressFlow(containing: step).count
    }

    var progressStepIndex: Int {
        OnboardingStep.progressFlow(containing: step).firstIndex(of: step) ?? 0
    }

    var isNamingValid: Bool {
        !personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !monitorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isAccountValid: Bool {
        !caregiverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && accountEmail.contains("@")
            && !accountPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && accountPassword.count >= 8
            && accountPassword == accountConfirmPassword
    }

    var isLoginValid: Bool {
        loginEmail.contains("@") && !loginPassword.isEmpty
    }

    var isPlacementComplete: Bool {
        completedPlacementItems.count == PlacementChecklistItem.allCases.count
    }

    var accountValidationMessage: String? {
        if caregiverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter your name."
        }
        if !accountEmail.contains("@") {
            return "Enter a valid email."
        }
        if accountPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a phone number."
        }
        if accountPassword.count < 8 {
            return "Password must be at least 8 characters."
        }
        if accountPassword != accountConfirmPassword {
            return "Passwords do not match."
        }
        return nil
    }

    func advance() {
        guard let next = step.next else { return }
        step = next
    }

    func startNewSetup() {
        step = .placement
    }

    func startExistingUserLogin() {
        step = .login
    }

    func goBack() {
        guard let previous = step.previous else { return }
        step = previous
    }

    func selectPersonOption(_ option: MonitoredPersonOption) {
        selectedPersonOption = option

        guard option != .custom else {
            personName = customPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }

        personName = option.title
        monitorName = "\(option.title)'s Bathroom"
    }

    func updateCustomPersonName(_ name: String) {
        customPersonName = name
        if selectedPersonOption == .custom {
            personName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !personName.isEmpty {
                monitorName = "\(personName)'s Bathroom"
            }
        }
    }

    func togglePlacementItem(_ item: PlacementChecklistItem) {
        if completedPlacementItems.contains(item) {
            completedPlacementItems.remove(item)
        } else {
            completedPlacementItems.insert(item)
        }
    }

    func discoverBluetooth() async {
        bluetoothState = .searching
        do {
            let device = try await services.bluetoothService.discoverMonitor()
            discoveredDevice = device
            bluetoothState = .found
            try await Task.sleep(for: .milliseconds(400))
            bluetoothState = .connecting
            let connectedDevice = try await services.bluetoothService.connect(to: device)
            discoveredDevice = connectedDevice
            services.identityStore.saveDeviceID(connectedDevice.id)
            bluetoothState = .connected
        } catch {
            bluetoothState = .failed
            errorMessage = error.localizedDescription
        }
    }

    func connectWiFi() async {
        guard let deviceID = discoveredDevice?.id else { return }
        wifiState = .connecting
        do {
            try await services.wifiService.connect(deviceID: deviceID, networkName: networkName, password: wifiPassword)
            wifiState = .connected
        } catch {
            wifiState = .failed
            errorMessage = error.localizedDescription
        }
    }

    func mockAuthenticate(method: AuthMethod) async {
        do {
            switch method {
            case .apple:
                try await services.authenticationService.signInWithApple()
            case .google:
                try await services.authenticationService.signInWithGoogle()
            case .email:
                try await services.authenticationService.continueWithEmail("koji@example.com")
            }
            advance()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signInExistingUser() async {
        guard isLoginValid else { return }
        do {
            try await services.authenticationService.continueWithEmail(loginEmail)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createAccount() async {
        guard isAccountValid else { return }
        do {
            try await services.authenticationService.continueWithEmail(accountEmail)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveDeviceIdentity() async {
        var device = discoveredDevice ?? MockData.stableDevice()
        device.displayName = monitorName
        device.monitoredPersonName = personName
        device.roomName = roomName
        services.identityStore.saveDeviceID(device.id)

        do {
            try await services.deviceRepository.saveDevice(device)
            discoveredDevice = device
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runMotionTest() async {
        motionTestState = .waiting
        do {
            let deviceID = discoveredDevice?.id ?? "bathroom-monitor-001"
            let success = try await services.bluetoothService.waitForMotionTest(deviceID: deviceID)
            motionTestState = success ? .success : .retry
        } catch {
            motionTestState = .retry
            errorMessage = error.localizedDescription
        }
    }
}

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case login
    case placement
    case bluetooth
    case wifi
    case naming
    case alerts
    case notifications
    case motionTest
    case account
    case complete

    var id: Int { rawValue }

    var next: OnboardingStep? {
        switch self {
        case .welcome, .login, .complete:
            nil
        case .placement:
            .bluetooth
        case .bluetooth:
            .wifi
        case .wifi:
            .naming
        case .naming:
            .alerts
        case .alerts:
            .notifications
        case .notifications:
            .motionTest
        case .motionTest:
            .account
        case .account:
            .complete
        }
    }

    var previous: OnboardingStep? {
        switch self {
        case .welcome:
            nil
        case .login, .placement:
            .welcome
        case .bluetooth:
            .placement
        case .wifi:
            .bluetooth
        case .naming:
            .wifi
        case .alerts:
            .naming
        case .notifications:
            .alerts
        case .motionTest:
            .notifications
        case .account:
            .motionTest
        case .complete:
            .account
        }
    }

    static func progressFlow(containing step: OnboardingStep) -> [OnboardingStep] {
        if step == .login {
            return [.welcome, .login]
        }

        return [
            .welcome,
            .placement,
            .bluetooth,
            .wifi,
            .naming,
            .alerts,
            .notifications,
            .motionTest,
            .account,
            .complete
        ]
    }
}

enum ProvisioningState: String {
    case idle = "Ready"
    case searching = "Searching"
    case found = "Monitor found"
    case connecting = "Connecting"
    case connected = "Connected"
    case failed = "Failed"
}

enum MotionTestState: String {
    case waiting = "Waiting for motion"
    case detected = "Motion detected"
    case success = "Test successful"
    case retry = "Retry"
}

enum AuthMethod {
    case apple
    case google
    case email
}

enum PlacementChecklistItem: String, CaseIterable, Identifiable {
    case power
    case height
    case aim
    case water
    case stable
    case pluggedIn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .power: "Plug the monitor into power"
        case .height: "Place it approximately 4-6 feet high"
        case .aim: "Aim it toward the monitored bathroom area or entrance"
        case .water: "Avoid direct water exposure"
        case .stable: "Avoid unstable surfaces"
        case .pluggedIn: "Keep it continuously plugged in"
        }
    }
}

enum MonitoredPersonOption: String, CaseIterable, Identifiable {
    case dad
    case mom
    case grandpa
    case grandma
    case uncle
    case aunt
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dad: "Dad"
        case .mom: "Mom"
        case .grandpa: "Grandpa"
        case .grandma: "Grandma"
        case .uncle: "Uncle"
        case .aunt: "Aunt"
        case .custom: "Custom"
        }
    }
}
