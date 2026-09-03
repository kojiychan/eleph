import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var rootViewModel: AppRootViewModel
    @StateObject var viewModel: SettingsViewModel
    @State private var showsSignOutConfirmation = false
    @State private var showsAddDevice = false

    var body: some View {
        NavigationStack {
            Form {
                if let message = viewModel.loadErrorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                monitorSection
                alertsAndNotificationsSection
                caregiverInfoSection
                accountSection
                supportSection
            }
            .navigationTitle("Settings")
            .task {
                await viewModel.load()
            }
            .onChange(of: viewModel.preferences) {
                Task { await viewModel.savePreferences() }
            }
            .confirmationDialog("Sign out of Eleph?", isPresented: $showsSignOutConfirmation, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        await rootViewModel.signOut()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can sign back in with your email and password.")
            }
            .sheet(isPresented: $showsAddDevice) {
                AddDeviceView(viewModel: AddDeviceViewModel(services: rootViewModel.services))
            }
        }
    }

    private var monitorSection: some View {
        Section("Monitor") {
            MonitorSettingsSummary(
                monitorName: viewModel.monitorName,
                roomName: viewModel.roomName,
                device: viewModel.device,
                preferences: viewModel.preferences
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if let device = viewModel.device {
                DisclosureGroup {
                    SettingsRow(title: "Device ID", detail: device.id, systemImage: "number")
                    SettingsRow(title: "Serial Number", detail: device.serialNumber, systemImage: "barcode")
                } label: {
                    Label("Technical Details", systemImage: "info.circle")
                }
            }
            SettingsRow(title: "Bluetooth and Wi-Fi setup", detail: "Coming in a later beta", systemImage: "wifi", tint: .secondary)
            Button {
                showsAddDevice = true
            } label: {
                SettingsRow(title: "Add Device", detail: "Bluetooth, QR, and Wi-Fi setup scaffold", systemImage: "plus.circle.fill")
            }
        }
    }

    private var alertsAndNotificationsSection: some View {
        Section("Alerts & Notifications") {
            AlertThresholdPicker(
                title: "Caution alert",
                description: "When Eleph should warn you that activity has been quiet longer than usual.",
                options: [8, 12, 18],
                value: $viewModel.preferences.cautionThresholdHours
            )
            AlertThresholdPicker(
                title: "Critical alert",
                description: "When Eleph should treat inactivity as higher priority.",
                options: [18, 24, 36],
                value: $viewModel.preferences.criticalThresholdHours
            )

            Toggle("Caution alerts", isOn: $viewModel.preferences.cautionAlertsEnabled)
            Toggle("Critical alerts", isOn: $viewModel.preferences.criticalAlertsEnabled)
            Toggle("Monitor disconnected", isOn: $viewModel.preferences.disconnectedAlertsEnabled)
            Toggle("Monitor reconnected", isOn: $viewModel.preferences.reconnectedAlertsEnabled)

            DisclosureGroup {
                DatePicker(
                    "Starts",
                    selection: binding(for: \.startsAt),
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    "Ends",
                    selection: binding(for: \.endsAt),
                    displayedComponents: .hourAndMinute
                )
                Text("Nighttime hours may be treated differently when determining unusual inactivity.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } label: {
                SettingsRow(title: "Nighttime schedule", detail: nighttimeSummary, systemImage: "moon.zzz.fill", tint: .indigo)
            }

            if let message = viewModel.alertValidationMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            Text("These preferences are saved for the beta. Push notification delivery will be enabled in a later build.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var caregiverInfoSection: some View {
        Section("Caregiver Info") {
            SettingsRow(title: "Emergency Contacts", detail: "2 contacts", systemImage: "phone.fill")
            SettingsRow(title: "Shared Caregivers", detail: "Invite trusted caregivers", systemImage: "person.2.fill")
            DisclosureGroup {
                TextField("Person being monitored", text: $viewModel.monitoredPersonName)
                TextField("Monitor name", text: $viewModel.monitorName)
                TextField("Room name", text: $viewModel.roomName)
            } label: {
                SettingsRow(title: "Care details", detail: "\(viewModel.monitoredPersonName) · \(viewModel.roomName)", systemImage: "person.text.rectangle.fill")
            }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            DisclosureGroup {
                TextField("First name", text: $viewModel.firstName)
                    .textContentType(.givenName)
                TextField("Last name", text: $viewModel.lastName)
                    .textContentType(.familyName)
                TextField("email@example.com", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .emailInputTraits()
                TextField("Phone number", text: $viewModel.phone)
                    .textContentType(.telephoneNumber)
                    .phoneInputTraits()
                Button {
                    Task { await viewModel.saveProfile() }
                } label: {
                    if viewModel.isSavingProfile {
                        Label("Saving", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label("Save Account", systemImage: "checkmark.circle.fill")
                    }
                }
                .disabled(viewModel.isSavingProfile)
            } label: {
                SettingsRow(title: "Account Details", detail: accountSummary, systemImage: "person.crop.circle.fill")
            }
            if let message = viewModel.accountValidationMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            Button(role: .destructive) {
                showsSignOutConfirmation = true
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    private var supportSection: some View {
        Section("Support") {
            NavigationLink {
                LegalDocumentView(document: .privacyPolicy)
            } label: {
                SettingsRow(title: "Privacy Policy", detail: "How Eleph handles data", systemImage: "hand.raised.fill")
            }
            NavigationLink {
                LegalDocumentView(document: .termsAndConditions)
            } label: {
                SettingsRow(title: "Terms and Conditions", detail: "Beta use and safety terms", systemImage: "doc.text.fill")
            }
            if let privacyPolicyURL = viewModel.legalLinks.privacyPolicyURL {
                Link(destination: privacyPolicyURL) {
                    SettingsRow(title: "Open Privacy Policy Online", detail: nil, systemImage: "safari.fill")
                }
            }
            if let termsURL = viewModel.legalLinks.termsURL {
                Link(destination: termsURL) {
                    SettingsRow(title: "Open Terms Online", detail: nil, systemImage: "safari.fill")
                }
            }
            Link(destination: viewModel.legalLinks.supportURL) {
                SettingsRow(title: "Help and Support", detail: "Email Eleph", systemImage: "questionmark.circle")
            }
            Link(destination: viewModel.legalLinks.dataDeletionURL) {
                SettingsRow(title: "Request Account/Data Deletion", detail: "Send a deletion request", systemImage: "trash.circle.fill", tint: .red)
            }
            SettingsRow(title: "About", detail: "Eleph Bathroom Monitor", systemImage: "info.circle")
        }
    }

    private var accountSummary: String {
        let name = [viewModel.firstName, viewModel.lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !name.isEmpty {
            return name
        }
        if !viewModel.email.isEmpty {
            return viewModel.email
        }
        return "Profile and contact info"
    }

    private var nighttimeSummary: String {
        let calendar = Calendar.current
        let start = calendar.date(from: viewModel.nighttimeSchedule.startsAt) ?? Date()
        let end = calendar.date(from: viewModel.nighttimeSchedule.endsAt) ?? Date()
        return "\(Formatters.time.string(from: start)) - \(Formatters.time.string(from: end))"
    }

    private func binding(for keyPath: WritableKeyPath<NighttimeSchedule, DateComponents>) -> Binding<Date> {
        Binding {
            Calendar.current.date(from: viewModel.nighttimeSchedule[keyPath: keyPath]) ?? Date()
        } set: { date in
            viewModel.nighttimeSchedule[keyPath: keyPath] = Calendar.current.dateComponents([.hour, .minute], from: date)
        }
    }
}

private struct MonitorSettingsSummary: View {
    let monitorName: String
    let roomName: String
    let device: MonitorDevice?
    let preferences: AlertPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "sensor.tag.radiowaves.forward")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 54, height: 54)
                        .background(.blue.opacity(0.12), in: Circle())

                    Circle()
                        .fill(connectionTint)
                        .frame(width: 14, height: 14)
                        .overlay {
                            Circle()
                                .stroke(AppColors.secondaryGroupedBackground, lineWidth: 2)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(monitorName)
                        .font(.headline)
                    Text(roomName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label(connectionTitle, systemImage: connectionSymbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(connectionTint)
                }

                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Inactivity threshold")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(preferences.cautionThresholdHours)h caution · \(preferences.criticalThresholdHours)h critical")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ThresholdScale(cautionThresholdHours: preferences.cautionThresholdHours, criticalThresholdHours: preferences.criticalThresholdHours)
            }
        }
        .padding(16)
        .background(AppColors.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.vertical, 4)
    }

    private var connectionTitle: String {
        guard let device else { return "Loading status" }
        return "\(device.connectionStatus.title) · last connected \(Formatters.relative(device.lastConnectedAt))"
    }

    private var connectionSymbol: String {
        device?.connectionStatus.symbol ?? "clock"
    }

    private var connectionTint: Color {
        device?.connectionStatus.tint ?? .secondary
    }
}

private struct ThresholdScale: View {
    let cautionThresholdHours: Int
    let criticalThresholdHours: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let criticalSeconds = max(Double(criticalThresholdHours) * 3600, 1)
                let cautionX = min(Double(cautionThresholdHours) * 3600 / criticalSeconds, 1) * width

                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        Capsule()
                            .fill(.green)
                            .frame(width: max(cautionX, 8))
                        Rectangle()
                            .fill(.yellow)
                            .frame(width: max(width - cautionX - 12, 8))
                        Capsule()
                            .fill(.red)
                            .frame(width: 12)
                    }
                    .opacity(0.85)
                    .clipShape(Capsule())

                    Rectangle()
                        .fill(.primary.opacity(0.35))
                        .frame(width: 2)
                        .offset(x: max(cautionX - 1, 0))
                }
            }
            .frame(height: 9)

            HStack {
                Text("Normal")
                    .foregroundStyle(.green)
                Spacer()
                Text("Caution")
                    .foregroundStyle(.yellow)
                Spacer()
                Text("Critical")
                    .foregroundStyle(.red)
            }
            .font(.caption2.weight(.semibold))
        }
    }
}

#Preview {
    MainTabPreview(scenario: .normalOnline)
}
