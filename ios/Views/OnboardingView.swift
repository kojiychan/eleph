import SwiftUI

struct OnboardingView: View {
    @StateObject var viewModel: OnboardingViewModel
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OnboardingProgressIndicator(
                    currentStep: viewModel.progressStepIndex,
                    totalSteps: viewModel.totalSteps
                )
                .padding()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        stepContent
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                footer
            }
            .background(AppColors.groupedBackground)
            .navigationTitle("Setup")
            .inlineNavigationTitleIfAvailable()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .welcome:
            welcome
        case .login:
            login
        case .placement:
            placement
        case .bluetooth:
            bluetooth
        case .wifi:
            wifi
        case .account:
            account
        case .naming:
            naming
        case .alerts:
            alerts
        case .notifications:
            notifications
        case .motionTest:
            motionTest
        case .complete:
            complete
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingHero(symbol: "heart.text.square.fill", title: "Welcome to Eleph", subtitle: "Privacy-preserving bathroom motion monitoring for caregivers.")
            Text("Eleph tracks motion activity, not video or audio, so you can see when it may be time to check in.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                Button {
                    viewModel.startNewSetup()
                } label: {
                    Label("New User", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    viewModel.startExistingUserLogin()
                } label: {
                    Label("Sign In", systemImage: "person.crop.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private var login: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingHero(symbol: "person.crop.circle.fill", title: "Sign in", subtitle: "Use your Eleph account to access a monitor that has already been set up.")
            TextField("Email", text: $viewModel.loginEmail)
                .textContentType(.username)
            SecureField("Password", text: $viewModel.loginPassword)
                .textContentType(.password)
            Text("For this beta, sign-in is prepared for the account system and will continue to the dashboard.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
    }

    private var placement: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingHero(symbol: "sensor.tag.radiowaves.forward.fill", title: "Place the monitor", subtitle: "Confirm each step once the monitor is in position.")
            placementChecklist

            if viewModel.isPlacementComplete {
                Label("Monitor placement complete", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var placementChecklist: some View {
        VStack(spacing: 10) {
            ForEach(PlacementChecklistItem.allCases) { item in
                let isComplete = viewModel.completedPlacementItems.contains(item)
                Button {
                    viewModel.togglePlacementItem(item)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isComplete ? .green : .secondary)
                        Text(item.title)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .background(isComplete ? Color.green.opacity(0.10) : AppColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isComplete ? .isSelected : [])
            }
        }
    }

    private var bluetooth: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingHero(symbol: "dot.radiowaves.left.and.right", title: "Bluetooth setup", subtitle: "Bluetooth setup will help connect nearby monitors in a later beta.")
            provisioningCard(state: viewModel.bluetoothState, device: viewModel.discoveredDevice)
            Button {
                Task { await viewModel.discoverBluetooth() }
            } label: {
                Label("Check Nearby Monitor", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Text("The app will use the monitor found over Bluetooth to connect to the right motion history.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var wifi: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingHero(symbol: "wifi", title: "Wi-Fi setup", subtitle: "Your current monitor should already be online and reporting motion activity.")
            TextField("Selected network", text: $viewModel.networkName)
                .textContentType(.none)
            SecureField("Wi-Fi password", text: $viewModel.wifiPassword)
            provisioningCard(state: viewModel.wifiState, device: viewModel.discoveredDevice)
            VStack(alignment: .leading, spacing: 8) {
                Label("Sending Wi-Fi credentials over Bluetooth", systemImage: "1.circle")
                Label("Device joining Wi-Fi", systemImage: "2.circle")
                Label("Device connecting to cloud", systemImage: "3.circle")
                Label("Monitor becoming online", systemImage: "4.circle")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            Button {
                Task { await viewModel.connectWiFi() }
            } label: {
                Label("Check Wi-Fi Setup", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Text("Reconnect setup will be enabled in a later beta.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingHero(symbol: "person.crop.circle.badge.checkmark", title: "Create your account", subtitle: "Your account saves this monitor setup and will let you receive alerts and sign in from another device.")
            TextField("Your name", text: $viewModel.caregiverName)
                .textContentType(.name)
            TextField("Email", text: $viewModel.accountEmail)
                .textContentType(.emailAddress)
            TextField("Phone number", text: $viewModel.accountPhone)
                .textContentType(.telephoneNumber)
            SecureField("Password", text: $viewModel.accountPassword)
                .textContentType(.newPassword)
            SecureField("Confirm password", text: $viewModel.accountConfirmPassword)
                .textContentType(.newPassword)

            if let message = viewModel.accountValidationMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private var naming: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingHero(symbol: "person.crop.circle.badge.questionmark", title: "Who are you monitoring?", subtitle: "These names help make alerts and activity updates easier to understand.")

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
                customPersonField
            }

            TextField("Monitor name", text: $viewModel.monitorName)
            TextField("Room name", text: $viewModel.roomName)
        }
        .textFieldStyle(.roundedBorder)
    }

    private var customPersonField: some View {
        TextField(
            "Person being monitored",
            text: Binding(
                get: { viewModel.customPersonName },
                set: { viewModel.updateCustomPersonName($0) }
            )
        )
    }

    private func personOptionBackground(_ option: MonitoredPersonOption) -> Color {
        viewModel.selectedPersonOption == option ? Color.blue.opacity(0.14) : AppColors.secondaryGroupedBackground
    }

    private var alerts: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingHero(symbol: "bell.badge.fill", title: "Choose alert timing", subtitle: "Caution is an early warning. Critical means it may be more urgent to check in.")
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
                    .foregroundStyle(.red)
            }
        }
    }

    private var notifications: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingHero(symbol: "app.badge.fill", title: "Choose notifications", subtitle: "These preferences are saved now. Notification delivery will be enabled in a later beta.")
            Toggle("Caution inactivity alerts", isOn: $viewModel.notifications.cautionAlertsEnabled)
            Toggle("Critical inactivity alerts", isOn: $viewModel.notifications.criticalAlertsEnabled)
            Toggle("Monitor disconnected", isOn: $viewModel.notifications.disconnectedAlertsEnabled)
            Toggle("Monitor reconnected", isOn: $viewModel.notifications.reconnectedAlertsEnabled)
        }
    }

    private var motionTest: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingHero(symbol: "figure.walk.motion", title: "Test motion", subtitle: "Walk in front of the monitor to confirm setup.")
            StatusBadge(title: viewModel.motionTestState.rawValue, systemImage: "figure.walk.motion", tint: viewModel.motionTestState == .success ? .green : .blue)
            Button {
                Task { await viewModel.runMotionTest() }
            } label: {
                Label("Run Motion Test", systemImage: "play.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var complete: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingHero(symbol: "checkmark.seal.fill", title: "Setup complete", subtitle: "Your bathroom monitor is ready for the dashboard.")
            checklist([
                "Monitor connected over Bluetooth",
                "Motion history connected",
                "Alert timing configured",
                "Notification preferences saved",
                "Account created"
            ])
        }
    }

    private var footer: some View {
        HStack {
            if viewModel.step.previous != nil {
                Button("Back") {
                    viewModel.goBack()
                }
            }

            Spacer()

            if viewModel.step != .welcome {
                Button(primaryButtonTitle) {
                    Task {
                        await primaryAction()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPrimaryDisabled)
            }
        }
        .padding()
        .background(.bar)
    }

    private var isPrimaryDisabled: Bool {
        (viewModel.step == .alerts && !viewModel.alertPreferences.isValid)
            || (viewModel.step == .naming && !viewModel.isNamingValid)
            || (viewModel.step == .account && !viewModel.isAccountValid)
            || (viewModel.step == .login && !viewModel.isLoginValid)
            || (viewModel.step == .placement && !viewModel.isPlacementComplete)
    }

    private var primaryButtonTitle: String {
        switch viewModel.step {
        case .welcome: ""
        case .login: "Sign In"
        case .placement: "I've Placed It"
        case .account: "Create Account"
        case .complete: "Go to Dashboard"
        default: "Continue"
        }
    }

    private func primaryAction() async {
        switch viewModel.step {
        case .welcome:
            break
        case .login:
            await viewModel.signInExistingUser()
            onComplete()
        case .naming:
            await viewModel.saveDeviceIdentity()
            viewModel.advance()
        case .account:
            await viewModel.createAccount()
            viewModel.advance()
        case .complete:
            await viewModel.saveDeviceIdentity()
            onComplete()
        default:
            viewModel.advance()
        }
    }

    private func onboardingHero(symbol: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 54))
                .foregroundStyle(.blue)
                .frame(width: 84, height: 84)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(title)
                .font(.largeTitle.weight(.bold))
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func checklist(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.primary)
            }
        }
        .font(.body)
    }

    private func provisioningCard(state: ProvisioningState, device: MonitorDevice?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusBadge(title: state.rawValue, systemImage: state == .failed ? "xmark.circle.fill" : "antenna.radiowaves.left.and.right", tint: state == .failed ? .red : .blue)
            if let device {
                LabeledContent("Device", value: device.displayName)
                LabeledContent("Signal", value: "Strong")
                LabeledContent("Device ID", value: device.id)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func authButton(_ title: String, symbol: String, method: AuthMethod) -> some View {
        Button {
            Task { await viewModel.mockAuthenticate(method: method) }
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

#Preview {
    OnboardingView(
        viewModel: OnboardingViewModel(services: AppServiceContainer.mock(scenario: .onboardingIncomplete)),
        onComplete: {}
    )
}
