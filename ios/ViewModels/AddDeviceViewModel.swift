import Foundation

@MainActor
final class AddDeviceViewModel: ObservableObject {
    @Published private(set) var state: AddDeviceOnboardingState = .idle
    @Published private(set) var setupDevices: [SetupDevice] = []
    @Published private(set) var selectedSetupDevice: SetupDevice?
    @Published private(set) var setupStatus: SetupStatus = .unknown
    @Published private(set) var provisioningStatus: ProvisioningStatus = .idle
    @Published private(set) var qrPayload: DeviceQRCodePayload?
    @Published var qrCodeText = "eleph://device?device_id=bathroom-monitor-001&name=Bathroom%20Monitor&token=abc123"
    @Published var displayName = "Bathroom Monitor"
    @Published var wifiSSID = ""
    @Published var wifiPassword = ""
    @Published var selectedPersonOption: MonitoredPersonOption = .grandma
    @Published var customPersonName = ""
    @Published var personName = "Grandma"
    @Published var roomName = "Hall Bathroom"
    @Published var alertPreferences = AlertPreferences.defaults
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
    @Published var showsAccountPassword = false
    @Published var showsAccountConfirmPassword = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var verificationEmail = ""
    @Published private(set) var errorMessage: String?

    private let services: AppServiceContainer

    init(services: AppServiceContainer) {
        self.services = services
    }

    var progressStepIndex: Int {
        AddDeviceOnboardingState.progressFlow.firstIndex(of: state.progressEquivalent) ?? 0
    }

    var totalSteps: Int {
        AddDeviceOnboardingState.progressFlow.count
    }

    var canContinue: Bool {
        switch state {
        case .idle, .intro, .bluetoothConnected, .qrValidated, .monitorReady, .notificationSettings, .verifyEmail, .success:
            true
        case .bluetoothDeviceFound:
            selectedSetupDevice != nil
        case .confirmingDeviceName:
            !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .wifiEntry:
            !wifiSSID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .careDetails:
            isCareDetailsValid
        case .alertSettings:
            alertPreferences.isValid
        case .accountCreation:
            isAccountValid && !isSubmitting
        case .failure:
            true
        case .bluetoothScanning, .bluetoothConnecting, .qrScanning, .sendingProvisioningPayload, .waitingForHeartbeat, .claimingDevice:
            false
        }
    }

    var isCareDetailsValid: Bool {
        !personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isAccountValid: Bool {
        !caregiverFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !caregiverLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && accountEmail.contains("@")
            && Self.phoneDigits(accountPhone).count == 10
            && accountPassword.count >= 8
            && accountPassword == accountConfirmPassword
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

    func start() {
        state = .intro
    }

    func scanForSetupDevices() async {
        state = .bluetoothScanning
        do {
            setupDevices = try await services.setupBluetoothService.scanForSetupDevices()
            guard let first = setupDevices.first else {
                throw AppServiceError.validation("No nearby Eleph monitors were found.")
            }
            selectedSetupDevice = first
            state = .bluetoothDeviceFound
        } catch {
            fail(error)
        }
    }

    func select(_ setupDevice: SetupDevice) {
        selectedSetupDevice = setupDevice
    }

    func connectToSelectedDevice() async {
        guard let selectedSetupDevice else {
            fail(AppServiceError.validation("Choose a nearby Eleph monitor."))
            return
        }

        state = .bluetoothConnecting
        do {
            try await services.setupBluetoothService.connect(to: selectedSetupDevice)
            setupStatus = try await services.setupBluetoothService.readSetupStatus()
            guard setupStatus == .readyForProvisioning else {
                throw AppServiceError.validation("This monitor is not ready for setup.")
            }
            state = .bluetoothConnected
        } catch {
            fail(error)
        }
    }

    func beginQRScan() {
        state = .qrScanning
    }

    func validateQRCode() {
        do {
            let payload = try DeviceQRCodeParser.parse(qrCodeText)
            qrPayload = payload
            displayName = payload.defaultDisplayName
            state = .qrValidated
        } catch {
            fail(error)
        }
    }

    func confirmDeviceName() {
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail(AppServiceError.validation("Enter a display name for this monitor."))
            return
        }
        state = .wifiEntry
    }

    func sendProvisioningPayload() async {
        guard let qrPayload else {
            fail(AppServiceError.validation("Scan the QR code before sending Wi-Fi setup."))
            return
        }

        let payload = ProvisioningPayload(
            deviceID: qrPayload.deviceID,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            claimToken: qrPayload.claimToken,
            wifiSSID: wifiSSID.trimmingCharacters(in: .whitespacesAndNewlines),
            wifiPassword: wifiPassword
        )

        state = .sendingProvisioningPayload
        provisioningStatus = .receivingPayload

        do {
            try await services.setupBluetoothService.sendProvisioningPayload(payload)
            provisioningStatus = try await services.setupBluetoothService.observeProvisioningStatus()
            guard provisioningStatus != .failed else {
                throw AppServiceError.validation("The monitor could not finish Wi-Fi setup.")
            }

            state = .waitingForHeartbeat
            try await services.deviceHeartbeatService.waitForDeviceOnline(deviceID: qrPayload.deviceID, timeoutSeconds: 45)

            state = .claimingDevice
            try await services.devicePairingService.claimDevice(
                deviceID: qrPayload.deviceID,
                claimToken: qrPayload.claimToken,
                displayName: payload.displayName
            )

            services.identityStore.saveDeviceID(qrPayload.deviceID)
            state = .monitorReady
        } catch {
            fail(error)
        }
    }

    func selectPersonOption(_ option: MonitoredPersonOption) {
        selectedPersonOption = option

        guard option != .custom else {
            personName = customPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }

        personName = option.title
        displayName = "\(option.title)'s Bathroom"
    }

    func updateCustomPersonName(_ name: String) {
        customPersonName = name
        if selectedPersonOption == .custom {
            personName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !personName.isEmpty {
                displayName = "\(personName)'s Bathroom"
            }
        }
    }

    func saveCareDetails() async {
        guard let deviceID = qrPayload?.deviceID ?? services.identityStore.loadDeviceID() else { return }

        let device = MonitorDevice(
            id: deviceID,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            serialNumber: qrPayload?.hardwareSerial ?? "",
            roomName: roomName.trimmingCharacters(in: .whitespacesAndNewlines),
            monitoredPersonName: personName.trimmingCharacters(in: .whitespacesAndNewlines),
            connectionStatus: .online,
            lastConnectedAt: Date(),
            lastMotionAt: nil
        )

        do {
            try await services.deviceRepository.saveDevice(device)
        } catch {
            errorMessage = Formatters.friendlyError(error.localizedDescription)
        }
    }

    func saveAlertSettings() async {
        do {
            try await services.alertRepository.savePreferences(alertPreferences)
        } catch {
            errorMessage = Formatters.friendlyError(error.localizedDescription)
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
            state = .verifyEmail
            return false
        } catch {
            errorMessage = Formatters.friendlyError(error.localizedDescription)
            return false
        }
    }

    func retry() {
        switch state {
        case .failure(let retryState, _):
            state = retryState
        default:
            state = .intro
        }
    }

    func advance() async {
        switch state {
        case .idle:
            start()
        case .intro:
            await scanForSetupDevices()
        case .bluetoothDeviceFound:
            await connectToSelectedDevice()
        case .bluetoothConnected:
            beginQRScan()
        case .qrScanning:
            validateQRCode()
        case .qrValidated:
            state = .confirmingDeviceName
        case .confirmingDeviceName:
            confirmDeviceName()
        case .wifiEntry:
            await sendProvisioningPayload()
        case .monitorReady:
            state = .careDetails
        case .careDetails:
            await saveCareDetails()
            state = .alertSettings
        case .alertSettings:
            await saveAlertSettings()
            state = .notificationSettings
        case .notificationSettings:
            state = .accountCreation
        case .accountCreation:
            if await createAccount() {
                state = .success
            }
        case .verifyEmail:
            state = .success
        case .failure:
            retry()
        case .success, .bluetoothScanning, .bluetoothConnecting, .sendingProvisioningPayload, .waitingForHeartbeat, .claimingDevice:
            break
        }
    }

    private var accountRegistration: AccountRegistration {
        AccountRegistration(
            firstName: caregiverFirstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: caregiverLastName.trimmingCharacters(in: .whitespacesAndNewlines),
            email: accountEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: Self.phoneDigits(accountPhone),
            password: accountPassword,
            deviceID: qrPayload?.deviceID ?? services.identityStore.loadDeviceID() ?? services.betaMonitorDeviceID,
            monitoredPersonName: personName.trimmingCharacters(in: .whitespacesAndNewlines),
            relationship: selectedPersonOption == .custom ? nil : selectedPersonOption.title.lowercased(),
            monitorName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            roomName: roomName.trimmingCharacters(in: .whitespacesAndNewlines),
            alertPreferences: alertPreferences,
            notificationPreferences: notifications,
            nighttimeSchedule: .defaults
        )
    }

    private func fail(_ error: Error) {
        state = .failure(
            retryState: state.retryFallback,
            error: Formatters.friendlyError(error.localizedDescription)
        )
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

indirect enum AddDeviceOnboardingState: Equatable {
    case idle
    case intro
    case bluetoothScanning
    case bluetoothDeviceFound
    case bluetoothConnecting
    case bluetoothConnected
    case qrScanning
    case qrValidated
    case confirmingDeviceName
    case wifiEntry
    case sendingProvisioningPayload
    case waitingForHeartbeat
    case claimingDevice
    case monitorReady
    case careDetails
    case alertSettings
    case notificationSettings
    case accountCreation
    case verifyEmail
    case success
    case failure(retryState: AddDeviceOnboardingState, error: String)

    static let progressFlow: [AddDeviceOnboardingState] = [
        .intro,
        .bluetoothScanning,
        .bluetoothDeviceFound,
        .bluetoothConnecting,
        .bluetoothConnected,
        .qrScanning,
        .qrValidated,
        .confirmingDeviceName,
        .wifiEntry,
        .sendingProvisioningPayload,
        .waitingForHeartbeat,
        .claimingDevice,
        .monitorReady,
        .careDetails,
        .alertSettings,
        .notificationSettings,
        .accountCreation,
        .verifyEmail,
        .success
    ]

    var progressEquivalent: AddDeviceOnboardingState {
        switch self {
        case .failure(let retryState, _):
            retryState.progressEquivalent
        default:
            self
        }
    }

    var retryFallback: AddDeviceOnboardingState {
        switch self {
        case .bluetoothScanning, .bluetoothDeviceFound, .bluetoothConnecting:
            .intro
        case .qrScanning, .qrValidated, .confirmingDeviceName:
            .bluetoothConnected
        case .wifiEntry, .sendingProvisioningPayload:
            .wifiEntry
        case .waitingForHeartbeat, .claimingDevice:
            .sendingProvisioningPayload
        case .careDetails, .alertSettings, .notificationSettings, .accountCreation, .verifyEmail:
            .monitorReady
        default:
            .intro
        }
    }
}
