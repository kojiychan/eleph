import SwiftUI

struct AddDeviceView: View {
    @StateObject var viewModel: AddDeviceViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: AddDeviceField?
    let onComplete: (() -> Void)?

    init(viewModel: AddDeviceViewModel, onComplete: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OnboardingProgressIndicator(
                    currentStep: viewModel.progressStepIndex,
                    totalSteps: viewModel.totalSteps
                )
                .padding(.horizontal)
                .padding(.top, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        content
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                footer
            }
            .background(AppColors.groupedBackground)
            .navigationTitle("Add Device")
            .inlineNavigationTitleIfAvailable()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task {
                if viewModel.state == .idle {
                    viewModel.start()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .intro:
            hero(
                symbol: "sensor.tag.radiowaves.forward.fill",
                title: "Set up your Eleph monitor",
                subtitle: "First we connect to the nearby monitor over Bluetooth. Then the QR code assigns the monitor identity, and Wi-Fi is sent securely to the connected monitor."
            )
            setupSteps([
                "Find nearby Eleph monitor",
                "Connect over Bluetooth",
                "Scan the device QR code",
                "Send Wi-Fi setup",
                "Wait for cloud heartbeat"
            ])

        case .bluetoothScanning:
            hero(symbol: "dot.radiowaves.left.and.right", title: "Finding nearby monitor", subtitle: "Keep your phone close to the Eleph monitor while Bluetooth scans.")
            progressCard(title: "Scanning", detail: "Looking for Eleph Setup or Eleph Monitor", symbol: "antenna.radiowaves.left.and.right")

        case .bluetoothDeviceFound:
            hero(symbol: "list.bullet.rectangle", title: "Choose your monitor", subtitle: "Select the nearby Eleph monitor before scanning the QR code.")
            deviceList

        case .bluetoothConnecting:
            hero(symbol: "point.3.connected.trianglepath.dotted", title: "Connecting", subtitle: "Your phone is creating a temporary Bluetooth connection to the monitor.")
            progressCard(title: "Bluetooth connecting", detail: viewModel.selectedSetupDevice?.name ?? "Eleph Monitor", symbol: "link")

        case .bluetoothConnected:
            hero(symbol: "checkmark.circle.fill", title: "Bluetooth connected", subtitle: "Now scan the QR code on the monitor or packaging. The QR code assigns identity to this connected monitor.")
            statusRows([
                ("Phone connected to monitor", "checkmark.circle.fill", Color.green),
                ("Ready for provisioning", "bolt.badge.checkmark.fill", Color.blue),
                ("QR identity required next", "qrcode.viewfinder", Color.secondary)
            ])

        case .qrScanning:
            hero(symbol: "qrcode.viewfinder", title: "Scan QR code", subtitle: "The QR code confirms the device ID and claim token. It does not connect to the monitor.")
            qrInput

        case .qrValidated:
            hero(symbol: "checkmark.seal.fill", title: "QR code validated", subtitle: "This identity will be sent to the monitor over the active Bluetooth connection.")
            identityCard

        case .confirmingDeviceName:
            hero(symbol: "pencil.circle.fill", title: "Name this monitor", subtitle: "This name will appear on the dashboard and in alerts.")
            TextField("Display name", text: $viewModel.displayName)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .displayName)

        case .wifiEntry:
            hero(symbol: "wifi", title: "Connect monitor to Wi-Fi", subtitle: "Wi-Fi credentials are sent to the already-connected monitor over Bluetooth.")
            wifiForm

        case .sendingProvisioningPayload:
            hero(symbol: "arrow.up.circle.fill", title: "Sending setup", subtitle: "The phone is sending the device identity, claim token, and Wi-Fi credentials to the monitor over Bluetooth.")
            progressCard(title: "Provisioning monitor", detail: viewModel.provisioningStatus.rawValue.capitalized, symbol: "arrow.up.circle.fill")

        case .waitingForHeartbeat:
            hero(symbol: "waveform.path.ecg", title: "Waiting for heartbeat", subtitle: "The monitor is joining Wi-Fi and checking in with Supabase.")
            progressCard(title: "Checking cloud status", detail: "Waiting for the monitor to come online", symbol: "cloud.fill")

        case .claimingDevice:
            hero(symbol: "person.badge.key.fill", title: "Pairing monitor", subtitle: "Eleph is linking this monitor to your account.")
            progressCard(title: "Claiming device", detail: viewModel.qrPayload?.deviceID ?? "Eleph monitor", symbol: "person.badge.key.fill")

        case .monitorReady:
            hero(symbol: "checkmark.seal.fill", title: "Monitor is ready", subtitle: "The monitor is connected and checking in. Next, choose the names and alert settings that make the dashboard easier to understand.")
            statusRows([
                ("Bluetooth setup complete", "checkmark.circle.fill", Color.green),
                ("QR identity assigned", "qrcode", Color.green),
                ("Wi-Fi provisioning sent", "wifi", Color.green),
                ("Heartbeat received", "waveform.path.ecg", Color.green)
            ])

        case .careDetails:
            careDetails

        case .alertSettings:
            alertSettings

        case .notificationSettings:
            notificationSettings

        case .accountCreation:
            accountCreation

        case .verifyEmail:
            verifyEmail

        case .success:
            hero(symbol: "checkmark.seal.fill", title: "Setup complete", subtitle: "Your account and monitor settings are ready for the dashboard.")
            statusRows([
                ("Monitor connected", "sensor.tag.radiowaves.forward.fill", Color.green),
                ("Care details saved", "person.crop.circle.badge.checkmark", Color.green),
                ("Alert timing configured", "bell.badge.fill", Color.green),
                ("Account created", "person.badge.key.fill", Color.green)
            ])

        case .failure(_, let error):
            hero(symbol: "exclamationmark.triangle.fill", title: "Setup needs attention", subtitle: error)
            setupSteps([
                "Keep your phone close to the monitor",
                "Confirm the QR code belongs to this Eleph monitor",
                "Check the Wi-Fi network name and password",
                "Try again"
            ])
        }
    }

    private var deviceList: some View {
        VStack(spacing: 10) {
            ForEach(viewModel.setupDevices) { setupDevice in
                Button {
                    viewModel.select(setupDevice)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sensor.tag.radiowaves.forward")
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .frame(width: 34)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(setupDevice.name)
                                .font(.headline)
                            Text("\(setupDevice.advertisedName) · Signal \(setupDevice.signalStrength) dBm")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: viewModel.selectedSetupDevice == setupDevice ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(viewModel.selectedSetupDevice == setupDevice ? .blue : .secondary)
                    }
                    .padding(14)
                    .background(AppColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var qrInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Eleph QR link", text: $viewModel.qrCodeText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .qrCode)
            Text("Camera scanning will plug into this step later. For now, paste or use the mock QR payload.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let payload = viewModel.qrPayload {
                LabeledContent("Device ID", value: payload.deviceID)
                LabeledContent("Name", value: payload.defaultDisplayName)
                if let model = payload.model {
                    LabeledContent("Model", value: model)
                }
                if let serial = payload.hardwareSerial {
                    LabeledContent("Serial", value: serial)
                }
                LabeledContent("Claim token", value: "Ready")
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var wifiForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Wi-Fi network name", text: $viewModel.wifiSSID)
                .textContentType(.none)
                .focused($focusedField, equals: .wifiSSID)
            SecureField("Wi-Fi password", text: $viewModel.wifiPassword)
                .textContentType(.password)
                .focused($focusedField, equals: .wifiPassword)
            statusRows([
                ("Device identity will be sent over Bluetooth", "qrcode", Color.blue),
                ("Wi-Fi credentials will be sent over Bluetooth", "wifi", Color.blue),
                ("Pairing happens after heartbeat", "person.badge.key.fill", Color.secondary)
            ])
        }
        .textFieldStyle(.roundedBorder)
    }

    private var careDetails: some View {
        VStack(alignment: .leading, spacing: 18) {
            hero(symbol: "person.crop.circle.badge.questionmark", title: "Who are you monitoring?", subtitle: "These names help make alerts and activity updates easier to understand.")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(MonitoredPersonOption.allCases) { option in
                    Button {
                        viewModel.selectPersonOption(option)
                    } label: {
                        HStack {
                            Text(option.title)
                                .font(.body.weight(.semibold))
                            Spacer()
                            if viewModel.selectedPersonOption == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(14)
                        .frame(minHeight: 52)
                        .background(personOptionBackground(option), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(viewModel.selectedPersonOption == option ? .isSelected : [])
                }
            }

            if viewModel.selectedPersonOption == .custom {
                TextField(
                    "Person being monitored",
                    text: Binding(
                        get: { viewModel.customPersonName },
                        set: { viewModel.updateCustomPersonName($0) }
                    )
                )
            }

            TextField("Monitor name", text: $viewModel.displayName)
                .focused($focusedField, equals: .displayName)
            TextField("Room name", text: $viewModel.roomName)
                .focused($focusedField, equals: .roomName)

            Label("\(viewModel.displayName) - \(viewModel.roomName)", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
    }

    private var alertSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            hero(symbol: "bell.badge.fill", title: "Choose alert timing", subtitle: "Caution is an early warning. Critical means it may be more urgent to check in.")
            AlertThresholdPicker(
                title: "When would you like a caution alert?",
                description: "Default is 12 hours of inactivity.",
                options: [8, 12, 18],
                value: $viewModel.alertPreferences.cautionThresholdHours
            )
            AlertThresholdPicker(
                title: "When would you like a critical alert?",
                description: "Default is 24 hours of inactivity.",
                options: [18, 24, 36],
                value: $viewModel.alertPreferences.criticalThresholdHours
            )
            InactivityProgressBar(
                currentInactivity: 2 * 3600,
                cautionThresholdHours: viewModel.alertPreferences.cautionThresholdHours,
                criticalThresholdHours: viewModel.alertPreferences.criticalThresholdHours
            )
            if !viewModel.alertPreferences.isValid {
                Label("Critical threshold must be greater than caution threshold.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var notificationSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            hero(symbol: "app.badge.fill", title: "Choose notifications", subtitle: "These preferences are saved now. Push delivery will use these settings when notification automation is enabled.")
            Toggle("Caution inactivity alerts", isOn: $viewModel.notifications.cautionAlertsEnabled)
            Toggle("Critical inactivity alerts", isOn: $viewModel.notifications.criticalAlertsEnabled)
            Toggle("Monitor disconnected", isOn: $viewModel.notifications.disconnectedAlertsEnabled)
            Toggle("Monitor reconnected", isOn: $viewModel.notifications.reconnectedAlertsEnabled)
        }
    }

    private var accountCreation: some View {
        VStack(alignment: .leading, spacing: 18) {
            hero(symbol: "person.crop.circle.badge.checkmark", title: "Create your account", subtitle: "Your account saves this monitor setup and lets you receive alerts and sign in from another device.")
            TextField("First name", text: $viewModel.caregiverFirstName)
                .textContentType(.givenName)
                .focused($focusedField, equals: .firstName)
                .submitLabel(.next)
                .onSubmit { focusedField = .lastName }
            TextField("Last name", text: $viewModel.caregiverLastName)
                .textContentType(.familyName)
                .focused($focusedField, equals: .lastName)
                .submitLabel(.next)
                .onSubmit { focusedField = .accountEmail }
            TextField("email@example.com", text: $viewModel.accountEmail)
                .textContentType(.emailAddress)
                .emailInputTraits()
                .focused($focusedField, equals: .accountEmail)
                .submitLabel(.next)
                .onSubmit { focusedField = .accountPhone }
            TextField("Phone number", text: $viewModel.accountPhone)
                .textContentType(.telephoneNumber)
                .phoneInputTraits()
                .focused($focusedField, equals: .accountPhone)
                .submitLabel(.next)
                .onSubmit { focusedField = .accountPassword }
            passwordField(
                title: "Password",
                text: $viewModel.accountPassword,
                isVisible: $viewModel.showsAccountPassword
            )
            .focused($focusedField, equals: .accountPassword)
            .submitLabel(.next)
            .onSubmit { focusedField = .accountConfirmPassword }
            passwordField(
                title: "Confirm password",
                text: $viewModel.accountConfirmPassword,
                isVisible: $viewModel.showsAccountConfirmPassword
            )
            .focused($focusedField, equals: .accountConfirmPassword)
            .submitLabel(.go)

            if focusedField == .accountPassword || focusedField == .accountConfirmPassword || !viewModel.accountPassword.isEmpty {
                Label("Use at least 8 characters.", systemImage: viewModel.accountPassword.count >= 8 ? "checkmark.circle.fill" : "info.circle")
                    .font(.footnote)
                    .foregroundStyle(viewModel.accountPassword.count >= 8 ? .green : .secondary)
            }

            if let message = viewModel.accountValidationMessage ?? viewModel.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private var verifyEmail: some View {
        VStack(alignment: .leading, spacing: 18) {
            hero(
                symbol: "envelope.badge.fill",
                title: "Verify your email",
                subtitle: "We sent a confirmation link to \(viewModel.verificationEmail.isEmpty ? "your email address" : viewModel.verificationEmail)."
            )
            setupSteps([
                "Open the email from Eleph or Supabase",
                "Tap the confirmation link",
                "Return to Eleph after the link opens"
            ])
            Text("If the confirmation link opens a localhost page, the Supabase Auth redirect URL needs to be updated for this app.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button {
                if viewModel.state == .success {
                    onComplete?()
                    dismiss()
                } else {
                    Task { await viewModel.advance() }
                }
            } label: {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(primaryButtonTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canContinue)
        }
        .padding()
        .background(.bar)
    }

    private var isBusy: Bool {
        switch viewModel.state {
        case .bluetoothScanning, .bluetoothConnecting, .sendingProvisioningPayload, .waitingForHeartbeat, .claimingDevice:
            true
        default:
            viewModel.isSubmitting
        }
    }

    private var primaryButtonTitle: String {
        switch viewModel.state {
        case .idle, .intro:
            "Find Monitor"
        case .bluetoothDeviceFound:
            "Connect"
        case .bluetoothConnected:
            "Scan QR Code"
        case .qrScanning:
            "Validate QR Code"
        case .qrValidated:
            "Confirm Identity"
        case .confirmingDeviceName:
            "Continue"
        case .wifiEntry:
            "Send Setup"
        case .monitorReady:
            "Configure Settings"
        case .careDetails, .alertSettings, .notificationSettings:
            "Continue"
        case .accountCreation:
            viewModel.isSubmitting ? "Creating Account" : "Create Account"
        case .verifyEmail:
            "Finish Setup"
        case .failure:
            "Retry"
        case .success:
            "Go to Dashboard"
        default:
            "Working"
        }
    }

    private func personOptionBackground(_ option: MonitoredPersonOption) -> Color {
        viewModel.selectedPersonOption == option ? Color.blue.opacity(0.14) : AppColors.secondaryGroupedBackground
    }

    private func passwordField(title: String, text: Binding<String>, isVisible: Binding<Bool>) -> some View {
        HStack {
            Group {
                if isVisible.wrappedValue {
                    TextField(title, text: text)
                } else {
                    SecureField(title, text: text)
                }
            }
            .textContentType(.newPassword)

            Button {
                isVisible.wrappedValue.toggle()
            } label: {
                Image(systemName: isVisible.wrappedValue ? "eye.slash.fill" : "eye.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isVisible.wrappedValue ? "Hide password" : "Show password")
        }
    }

    private func hero(symbol: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .frame(width: 78, height: 78)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(title)
                .font(.largeTitle.weight(.bold))
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func setupSteps(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                Label(step, systemImage: "\(index + 1).circle.fill")
            }
        }
        .font(.body)
        .foregroundStyle(.secondary)
    }

    private func progressCard(title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            ProgressView()
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func statusRows(_ rows: [(String, String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Label {
                    Text(row.0)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: row.1)
                        .foregroundStyle(row.2)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private enum AddDeviceField: Hashable {
    case qrCode
    case displayName
    case roomName
    case wifiSSID
    case wifiPassword
    case firstName
    case lastName
    case accountEmail
    case accountPhone
    case accountPassword
    case accountConfirmPassword
}

#Preview("Add Device") {
    AddDeviceView(viewModel: AddDeviceViewModel(services: AppServiceContainer.mock()))
}
