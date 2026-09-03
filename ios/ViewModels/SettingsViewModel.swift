import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var device: MonitorDevice?
    @Published var preferences = AlertPreferences.defaults
    @Published var nighttimeSchedule = NighttimeSchedule.defaults
    @Published var monitoredPersonName = "Grandma"
    @Published var monitorName = "Grandma's Bathroom"
    @Published var roomName = "Hall Bathroom"
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var email = ""
    @Published var phone = "" {
        didSet {
            let formatted = Self.formatPhoneNumber(phone)
            if phone != formatted {
                phone = formatted
            }
        }
    }
    @Published var isSavingProfile = false
    @Published var alertValidationMessage: String?
    @Published var accountValidationMessage: String?
    @Published var loadErrorMessage: String?

    private let services: AppServiceContainer

    init(services: AppServiceContainer) {
        self.services = services
    }

    var legalLinks: LegalLinks {
        services.legalLinks
    }

    func load() async {
        do {
            device = try await services.deviceRepository.fetchDevice()
            preferences = try await services.alertRepository.fetchPreferences()
            let profile = try? await services.authenticationService.loadProfile()
            if let device {
                monitoredPersonName = device.monitoredPersonName
                monitorName = device.displayName
                roomName = device.roomName
            }
            if let profile {
                firstName = profile.firstName
                lastName = profile.lastName
                email = profile.email
                phone = Self.formatPhoneNumber(profile.phone)
            }
        } catch {
            loadErrorMessage = Formatters.friendlyError(error.localizedDescription)
        }
    }

    func savePreferences() async {
        guard preferences.isValid else {
            alertValidationMessage = "Critical alert must be greater than caution alert."
            return
        }

        do {
            try await services.alertRepository.savePreferences(preferences)
            alertValidationMessage = nil
        } catch {
            alertValidationMessage = Formatters.friendlyError(error.localizedDescription)
        }
    }

    func saveProfile() async {
        guard !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              email.contains("@"),
              Self.phoneDigits(phone).count == 10 else {
            accountValidationMessage = "Enter a valid name, email, and phone number."
            return
        }

        do {
            isSavingProfile = true
            defer { isSavingProfile = false }
            try await services.authenticationService.saveProfile(
                AccountProfile(
                    firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                    lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    phone: Self.phoneDigits(phone)
                )
            )
            accountValidationMessage = nil
        } catch {
            accountValidationMessage = Formatters.friendlyError(error.localizedDescription)
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
