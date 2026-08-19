import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var device: MonitorDevice?
    @Published var preferences = AlertPreferences.defaults
    @Published var nighttimeSchedule = NighttimeSchedule.defaults
    @Published var monitoredPersonName = "Grandma"
    @Published var monitorName = "Grandma's Bathroom"
    @Published var roomName = "Hall Bathroom"
    @Published var validationMessage: String?

    private let services: AppServiceContainer

    init(services: AppServiceContainer) {
        self.services = services
    }

    func load() async {
        do {
            device = try await services.deviceRepository.fetchDevice()
            preferences = try await services.alertRepository.fetchPreferences()
            if let device {
                monitoredPersonName = device.monitoredPersonName
                monitorName = device.displayName
                roomName = device.roomName
            }
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    func savePreferences() async {
        guard preferences.isValid else {
            validationMessage = "Critical alert must be greater than caution alert."
            return
        }

        do {
            try await services.alertRepository.savePreferences(preferences)
            validationMessage = nil
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}
