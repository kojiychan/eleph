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
    @Published var caregiverFirstName = ""
    @Published var caregiverLastName = ""
    @Published var accountEmail = ""
    @Published var accountPhone = "" {
        didSet {
            let formatted = Self.formatPhoneNumber(accountPhone)
            if accountPhone != formatted {
                accountPhone = formatted
            }
        }
    }
    @Published var accountPassword = ""
    @Published var accountConfirmPassword = ""
    @Published var loginEmail = ""
    @Published var loginPassword = ""
    @Published var completedPlacementItems: Set<PlacementChecklistItem> = []
    @Published var isSubmitting = false
    @Published var showsAccountPassword = false
    @Published var showsAccountConfirmPassword = false
    @Published var showsLoginPassword = false
    @Published var errorMessage: String?
    @Published var verificationEmail = ""

    private let services: AppServiceContainer

    init(services: AppServiceContainer) {
        self.services = services
        configureBetaMonitor()
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
        !caregiverFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !caregiverLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        if caregiverFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter your first name."
        }
        if caregiverLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter your last name."
        }
        if !accountEmail.contains("@") {
            return "Enter a valid email."
        }
        if accountPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a phone number."
        }
        if Self.phoneDigits(accountPhone).count != 10 {
            return "Enter a 10-digit phone number."
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
        errorMessage = nil
        guard let next = step.next else { return }
        step = next
    }

    func startNewSetup() {
        errorMessage = nil
        configureBetaMonitor()
        step = .naming
    }

    func startExistingUserLogin() {
        errorMessage = nil
        if !accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            loginEmail = accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        }
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
            Haptics.success()
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

    func signInExistingUser() async -> Bool {
        guard isLoginValid else { return false }
        do {
            isSubmitting = true
            defer { isSubmitting = false }
            errorMessage = nil
            try await services.authenticationService.signIn(email: loginEmail, password: loginPassword)
            return true
        } catch {
            errorMessage = Formatters.friendlyError(error.localizedDescription)
            return false
        }
    }

    func createAccount() async -> Bool {
        guard isAccountValid else { return false }
        do {
            isSubmitting = true
            defer { isSubmitting = false }
            errorMessage = nil
            try await services.authenticationService.createAccount(accountRegistration)
            return true
        } catch let verificationRequired as AccountVerificationRequired {
            verificationEmail = verificationRequired.email
            loginEmail = verificationRequired.email
            step = .verifyEmail
            return false
        } catch {
            errorMessage = Formatters.friendlyError(error.localizedDescription)
            return false
        }
    }

    func saveDeviceIdentity() async {
        var device = discoveredDevice ?? MockData.stableDevice(id: currentMonitorDeviceID)
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
            let deviceID = currentMonitorDeviceID
            let success = try await services.bluetoothService.waitForMotionTest(deviceID: deviceID)
            motionTestState = success ? .success : .retry
        } catch {
            motionTestState = .retry
            errorMessage = error.localizedDescription
        }
    }

    private var accountRegistration: AccountRegistration {
        AccountRegistration(
            firstName: caregiverFirstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: caregiverLastName.trimmingCharacters(in: .whitespacesAndNewlines),
            email: accountEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: Self.phoneDigits(accountPhone),
            password: accountPassword,
            deviceID: currentMonitorDeviceID,
            monitoredPersonName: personName,
            relationship: selectedPersonOption == .custom ? nil : selectedPersonOption.title.lowercased(),
            monitorName: monitorName,
            roomName: roomName,
            alertPreferences: alertPreferences,
            notificationPreferences: notifications,
            nighttimeSchedule: nighttimeSchedule
        )
    }

    private var currentMonitorDeviceID: String {
        discoveredDevice?.id ?? services.identityStore.loadDeviceID() ?? services.betaMonitorDeviceID
    }

    private func configureBetaMonitor() {
        let deviceID = services.betaMonitorDeviceID
        services.identityStore.saveDeviceID(deviceID)
        if discoveredDevice == nil {
            discoveredDevice = MockData.stableDevice(id: deviceID)
        }
    }

    private static func phoneDigits(_ value: String) -> String {
        value.filter(\.isNumber)
    }

    private static func formatPhoneNumber(_ value: String) -> String {
        let digits = String(phoneDigits(value).prefix(10))
        var output = ""

        for (index, character) in digits.enumerated() {
            if index == 0 {
                output.append("(")
            }
            if index == 3 {
                output.append(") ")
            }
            if index == 6 {
                output.append("-")
            }
            output.append(character)
        }

        return output
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
    case verifyEmail
    case complete

    var id: Int { rawValue }

    var next: OnboardingStep? {
        switch self {
        case .welcome, .login, .complete:
            nil
        case .placement, .bluetooth:
            .wifi
        case .wifi, .motionTest:
            .account
        case .naming:
            .alerts
        case .alerts:
            .notifications
        case .notifications:
            .account
        case .account:
            .complete
        case .verifyEmail:
            .login
        }
    }

    var previous: OnboardingStep? {
        switch self {
        case .welcome:
            nil
        case .login, .naming:
            .welcome
        case .placement:
            .welcome
        case .bluetooth:
            .placement
        case .wifi:
            .bluetooth
        case .alerts:
            .naming
        case .notifications:
            .alerts
        case .motionTest:
            .notifications
        case .account:
            .notifications
        case .verifyEmail:
            .account
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
            .naming,
            .alerts,
            .notifications,
            .account,
            .verifyEmail,
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
