import SwiftUI

struct SettingsView: View {
    @StateObject var viewModel: SettingsViewModel

    var body: some View {
        NavigationStack {
            Form {
                monitorSection
                alertSection
                nighttimeSection
                notificationsSection
                caregiverSection
                accountSection
            }
            .navigationTitle("Settings")
            .task {
                await viewModel.load()
            }
            .onChange(of: viewModel.preferences) {
                Task { await viewModel.savePreferences() }
            }
        }
    }

    private var monitorSection: some View {
        Section("Monitor") {
            SettingsRow(title: viewModel.monitorName, detail: viewModel.roomName, systemImage: "sensor.tag.radiowaves.forward")
            if let device = viewModel.device {
                SettingsRow(title: device.connectionStatus.title, detail: "Last connected \(Formatters.relative(device.lastConnectedAt))", systemImage: device.connectionStatus.symbol, tint: device.connectionStatus.tint)
                SettingsRow(title: "Device ID", detail: device.id, systemImage: "number")
                SettingsRow(title: "Serial Number", detail: device.serialNumber, systemImage: "barcode")
            }
            Button {
            } label: {
                Label("Wi-Fi Setup", systemImage: "wifi")
            }
            Button {
            } label: {
                Label("Reconnect Monitor", systemImage: "arrow.clockwise")
            }
        }
    }

    private var alertSection: some View {
        Section("Alert Settings") {
            AlertThresholdPicker(
                title: "Caution Alert",
                description: "Sends a standard notification when inactivity exceeds this period.",
                options: [8, 12, 18],
                value: $viewModel.preferences.cautionThresholdHours
            )
            AlertThresholdPicker(
                title: "Critical Alert",
                description: "Sends a higher-priority alert when inactivity exceeds this period.",
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
        }
    }

    private var caregiverSection: some View {
        Section("Caregiver Settings") {
            SettingsRow(title: "Emergency Contacts", detail: "2 contacts", systemImage: "phone.fill")
            SettingsRow(title: "Shared Caregivers", detail: "Invite trusted caregivers", systemImage: "person.2.fill")
            TextField("Person being monitored", text: $viewModel.monitoredPersonName)
            TextField("Monitor name", text: $viewModel.monitorName)
            TextField("Room name", text: $viewModel.roomName)
        }
    }

    private var accountSection: some View {
        Section("Account and Support") {
            SettingsRow(title: "Account", detail: "Koji", systemImage: "person.crop.circle")
            SettingsRow(title: "Privacy", detail: "Privacy-preserving motion monitoring", systemImage: "hand.raised.fill")
            SettingsRow(title: "Help and Support", detail: nil, systemImage: "questionmark.circle")
            SettingsRow(title: "About", detail: "Eleph Bathroom Monitor", systemImage: "info.circle")
            Button(role: .destructive) {
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
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

#Preview {
    MainTabPreview(scenario: .normalOnline)
}
