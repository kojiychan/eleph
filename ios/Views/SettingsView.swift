import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var rootViewModel: AppRootViewModel
    @StateObject var viewModel: SettingsViewModel
    @State private var showsSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                monitorSection
                alertSection
                nighttimeSection
                notificationsSection
                caregiverSection
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
        }
    }

    private var monitorSection: some View {
        Section("Monitor") {
            SettingsRow(title: viewModel.monitorName, detail: viewModel.roomName, systemImage: "sensor.tag.radiowaves.forward")
            if let device = viewModel.device {
                SettingsRow(title: device.connectionStatus.title, detail: "Last connected \(Formatters.relative(device.lastConnectedAt))", systemImage: device.connectionStatus.symbol, tint: device.connectionStatus.tint)
                DisclosureGroup {
                    SettingsRow(title: "Device ID", detail: device.id, systemImage: "number")
                    SettingsRow(title: "Serial Number", detail: device.serialNumber, systemImage: "barcode")
                } label: {
                    Label("Technical Details", systemImage: "info.circle")
                }
            }
            SettingsRow(title: "Bluetooth and Wi-Fi setup", detail: "Coming in a later beta", systemImage: "wifi", tint: .secondary)
        }
    }

    private var alertSection: some View {
        Section("Alert Settings") {
            AlertThresholdPicker(
                title: "Caution Alert",
                description: "Used for the standard inactivity alert preference.",
                options: [8, 12, 18],
                value: $viewModel.preferences.cautionThresholdHours
            )
            AlertThresholdPicker(
                title: "Critical Alert",
                description: "Used for the higher-priority inactivity alert preference.",
                options: [18, 24, 36],
                value: $viewModel.preferences.criticalThresholdHours
            )
            if let message = viewModel.validationMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private var nighttimeSection: some View {
        Section("Nighttime Schedule") {
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
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Caution alerts", isOn: $viewModel.preferences.cautionAlertsEnabled)
            Toggle("Critical alerts", isOn: $viewModel.preferences.criticalAlertsEnabled)
            Toggle("Monitor disconnected", isOn: $viewModel.preferences.disconnectedAlertsEnabled)
            Toggle("Monitor reconnected", isOn: $viewModel.preferences.reconnectedAlertsEnabled)
            Text("These preferences are saved for the beta. Push notification delivery will be enabled in a later build.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var caregiverSection: some View {
        Section("Caregivers") {
            SettingsRow(title: "Emergency Contacts", detail: "2 contacts", systemImage: "phone.fill")
            SettingsRow(title: "Shared Caregivers", detail: "Invite trusted caregivers", systemImage: "person.2.fill")
            TextField("Person being monitored", text: $viewModel.monitoredPersonName)
            TextField("Monitor name", text: $viewModel.monitorName)
            TextField("Room name", text: $viewModel.roomName)
        }
    }

    private var accountSection: some View {
        Section("Account") {
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

    private func binding(for keyPath: WritableKeyPath<NighttimeSchedule, DateComponents>) -> Binding<Date> {
        Binding {
            Calendar.current.date(from: viewModel.nighttimeSchedule[keyPath: keyPath]) ?? Date()
        } set: { date in
            viewModel.nighttimeSchedule[keyPath: keyPath] = Calendar.current.dateComponents([.hour, .minute], from: date)
        }
    }
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

#Preview {
    MainTabPreview(scenario: .normalOnline)
}
