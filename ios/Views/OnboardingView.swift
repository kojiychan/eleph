import SwiftUI

struct OnboardingView: View {
    @StateObject var viewModel: OnboardingViewModel
    @FocusState private var focusedField: OnboardingField?
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
            Text("For this TestFlight beta, your account will be linked to the bathroom monitor that is already online.")
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
            TextField("email@example.com", text: $viewModel.loginEmail)
                .textContentType(.username)
                .emailInputTraits()
                .focused($focusedField, equals: .loginEmail)
                .submitLabel(.next)
                .onSubmit { focusedField = .loginPassword }
            passwordField(
                title: "Password",
                text: $viewModel.loginPassword,
                isVisible: $viewModel.showsLoginPassword,
                isNewPassword: false
            )
            .focused($focusedField, equals: .loginPassword)
            .submitLabel(.go)
            .onSubmit {
                Task {
                    if await viewModel.signInExistingUser() {
                        onComplete()
                    }
                }
            }
            if let message = viewModel.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
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
            onboardingHero(symbol: "dot.radiowaves.left.and.right", title: "Find Monitor", subtitle: "The app will look for a nearby monitor and connect it to this setup.")
            provisioningCard(state: viewModel.bluetoothState, device: viewModel.discoveredDevice)
            Button {
                Task { await viewModel.discoverBluetooth() }
            } label: {
                Label("Check Nearby Monitor", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Text("The monitor identity is saved quietly after connection so the dashboard loads the right motion history.")
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
            Text("You can continue without changing Wi-Fi for this beta.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingHero(symbol: "person.crop.circle.badge.checkmark", title: "Create your account", subtitle: "Your account saves this monitor setup and will let you receive alerts and sign in from another device.")
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
                isVisible: $viewModel.showsAccountPassword,
                isNewPassword: true
            )
            .focused($focusedField, equals: .accountPassword)
            .submitLabel(.next)
            .onSubmit { focusedField = .accountConfirmPassword }
            passwordField(
                title: "Confirm password",
                text: $viewModel.accountConfirmPassword,
                isVisible: $viewModel.showsAccountConfirmPassword,
                isNewPassword: true
            )
            .focused($focusedField, equals: .accountConfirmPassword)
            .submitLabel(.go)
            .onSubmit {
                Task {
                    if await viewModel.createAccount() {
                        viewModel.advance()
                    }
                }
            }

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

            Label("\(viewModel.monitorName) - \(viewModel.roomName)", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
    }

    private func passwordField(
        title: String,
        text: Binding<String>,
        isVisible: Binding<Bool>,
        isNewPassword: Bool
    ) -> some View {
        HStack {
            Group {
                if isVisible.wrappedValue {
                    TextField(title, text: text)
                } else {
                    SecureField(title, text: text)
                }
            }
            .textContentType(isNewPassword ? .newPassword : .password)

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
                "Beta monitor assigned",
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
                Button {
                    Task {
                        await primaryAction()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(primaryButtonTitle)
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
            || viewModel.isSubmitting
    }

    private var primaryButtonTitle: String {
        switch viewModel.step {
        case .welcome: ""
        case .login: viewModel.isSubmitting ? "Signing In" : "Sign In"
        case .placement: "I've Placed It"
        case .account: viewModel.isSubmitting ? "Creating Account" : "Create Account"
        case .complete: "Go to Dashboard"
        default: "Continue"
        }
    }

    private func primaryAction() async {
        switch viewModel.step {
        case .welcome:
            break
        case .login:
            if await viewModel.signInExistingUser() {
                onComplete()
            }
        case .naming:
            await viewModel.saveDeviceIdentity()
            viewModel.advance()
        case .account:
            if await viewModel.createAccount() {
                viewModel.advance()
            }
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

private extension View {
    @ViewBuilder
    func emailInputTraits() -> some View {
        #if os(iOS)
        self
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }

    @ViewBuilder
    func phoneInputTraits() -> some View {
        #if os(iOS)
        self.keyboardType(.phonePad)
        #else
        self
        #endif
    }
}

private enum OnboardingField: Hashable {
    case loginEmail
    case loginPassword
    case firstName
    case lastName
    case accountEmail
    case accountPhone
    case accountPassword
    case accountConfirmPassword
}
