import Foundation
import Supabase

actor SupabaseAuthenticationService: AuthenticationService {
    private static let authCallbackURL = URL(string: "eleph://auth-callback")!

    private let client: SupabaseClient
    private let identityStore: DeviceIdentityStore
    private let betaDeviceID: String

    init(configuration: AppConfiguration, identityStore: DeviceIdentityStore) {
        self.client = SupabaseClient(
            supabaseURL: configuration.supabaseURL,
            supabaseKey: configuration.supabaseAnonKey
        )
        self.identityStore = identityStore
        self.betaDeviceID = configuration.monitorDeviceID
    }

    func signInWithApple() async throws {
        throw AppServiceError.validation("Sign in with Apple is not enabled for this beta.")
    }

    func signInWithGoogle() async throws {
        throw AppServiceError.validation("Sign in with Google is not enabled for this beta.")
    }

    func continueWithEmail(_ email: String) async throws {
        throw AppServiceError.validation("Enter your email and password to sign in.")
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
        let session = try await client.auth.session
        try await ensureBetaDeviceLink(userID: session.user.id)
    }

    func createAccount(_ registration: AccountRegistration) async throws {
        let normalizedEmail = registration.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPhone = registration.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata: [String: AnyJSON] = [
            "first_name": .string(registration.firstName),
            "last_name": .string(registration.lastName),
            "display_name": .string(registration.displayName),
            "phone": .string(normalizedPhone)
        ]

        let response = try await client.auth.signUp(
            email: normalizedEmail,
            password: registration.password,
            data: metadata,
            redirectTo: Self.authCallbackURL
        )

        let userID: UUID
        switch response {
        case .session(let session):
            userID = session.user.id
        case .user:
            throw AppServiceError.validation("Check your email to confirm your account, then sign in to finish setup.")
        }

        identityStore.saveDeviceID(registration.deviceID)
        try await upsertProfile(
            userID: userID,
            profile: AccountProfile(
                firstName: registration.firstName,
                lastName: registration.lastName,
                email: normalizedEmail,
                phone: normalizedPhone
            )
        )
        try await upsertUserDevice(userID: userID, deviceID: registration.deviceID)
        try await upsertDeviceSettings(userID: userID, registration: registration)
    }

    func handleAuthCallback(_ url: URL) async throws {
        let session = try await client.auth.session(from: url)
        try await ensureBetaDeviceLink(userID: session.user.id)
    }

    func loadProfile() async throws -> AccountProfile {
        let session = try await client.auth.session
        let rows: [ProfileRow] = try await client
            .from("profiles")
            .select()
            .eq("id", value: session.user.id.uuidString)
            .limit(1)
            .execute()
            .value

        if let row = rows.first {
            return AccountProfile(
                firstName: row.firstName ?? "",
                lastName: row.lastName ?? "",
                email: row.email ?? session.user.email ?? "",
                phone: row.phone ?? session.user.phone ?? ""
            )
        }

        return AccountProfile(
            firstName: "",
            lastName: "",
            email: session.user.email ?? "",
            phone: session.user.phone ?? ""
        )
    }

    func saveProfile(_ profile: AccountProfile) async throws {
        let session = try await client.auth.session
        try await client.auth.update(
            user: UserAttributes(
                data: [
                    "first_name": .string(profile.firstName),
                    "last_name": .string(profile.lastName),
                    "display_name": .string(profile.displayName),
                    "phone": .string(profile.phone)
                ]
            )
        )
        try await upsertProfile(userID: session.user.id, profile: profile)
    }

    func hasActiveSession() async -> Bool {
        do {
            _ = try await client.auth.session
            return true
        } catch {
            return false
        }
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    private func upsertProfile(userID: UUID, profile: AccountProfile) async throws {
        try await client
            .from("profiles")
            .upsert(
                ProfileMutation(
                    id: userID,
                    firstName: profile.firstName,
                    lastName: profile.lastName,
                    displayName: profile.displayName,
                    email: profile.email.trimmingCharacters(in: .whitespacesAndNewlines),
                    phone: profile.phone.trimmingCharacters(in: .whitespacesAndNewlines)
                ),
                onConflict: "id",
                returning: .minimal
            )
            .execute()
    }

    private func upsertUserDevice(userID: UUID, deviceID: String) async throws {
        try await client
            .from("user_devices")
            .upsert(
                UserDeviceMutation(userID: userID, deviceID: deviceID, role: "owner"),
                onConflict: "user_id,device_id",
                returning: .minimal
            )
            .execute()
    }

    private func ensureBetaDeviceLink(userID: UUID) async throws {
        let deviceID = identityStore.loadDeviceID() ?? betaDeviceID
        identityStore.saveDeviceID(deviceID)
        try await upsertUserDevice(userID: userID, deviceID: deviceID)
    }

    private func upsertDeviceSettings(userID: UUID, registration: AccountRegistration) async throws {
        try await client
            .from("device_settings")
            .upsert(
                DeviceSettingsMutation(
                    userID: userID,
                    deviceID: registration.deviceID,
                    monitoredPersonName: registration.monitoredPersonName,
                    relationship: registration.relationship,
                    monitorName: registration.monitorName,
                    roomName: registration.roomName,
                    cautionInactivityMinutes: registration.alertPreferences.cautionThresholdHours * 60,
                    criticalInactivityMinutes: registration.alertPreferences.criticalThresholdHours * 60,
                    quietHoursStart: Self.timeString(from: registration.nighttimeSchedule.startsAt),
                    quietHoursEnd: Self.timeString(from: registration.nighttimeSchedule.endsAt),
                    cautionAlertsEnabled: registration.notificationPreferences.cautionAlertsEnabled,
                    criticalAlertsEnabled: registration.notificationPreferences.criticalAlertsEnabled,
                    pushNotificationsEnabled: registration.notificationPreferences.cautionAlertsEnabled || registration.notificationPreferences.criticalAlertsEnabled,
                    smsNotificationsEnabled: false,
                    disconnectedAlertsEnabled: registration.notificationPreferences.disconnectedAlertsEnabled,
                    reconnectedAlertsEnabled: registration.notificationPreferences.reconnectedAlertsEnabled
                ),
                onConflict: "user_id,device_id",
                returning: .minimal
            )
            .execute()
    }

    private static func timeString(from components: DateComponents) -> String {
        String(format: "%02d:%02d:00", components.hour ?? 0, components.minute ?? 0)
    }
}

private struct ProfileMutation: Encodable {
    let id: UUID
    let firstName: String
    let lastName: String
    let displayName: String
    let email: String
    let phone: String

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case displayName = "display_name"
        case email
        case phone
    }
}

private struct ProfileRow: Decodable {
    let firstName: String?
    let lastName: String?
    let email: String?
    let phone: String?

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case phone
    }
}

private struct UserDeviceMutation: Encodable {
    let userID: UUID
    let deviceID: String
    let role: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case deviceID = "device_id"
        case role
    }
}

private struct DeviceSettingsMutation: Encodable {
    let userID: UUID
    let deviceID: String
    let monitoredPersonName: String
    let relationship: String?
    let monitorName: String
    let roomName: String
    let cautionInactivityMinutes: Int
    let criticalInactivityMinutes: Int
    let quietHoursStart: String
    let quietHoursEnd: String
    let timezone: String
    let cautionAlertsEnabled: Bool
    let criticalAlertsEnabled: Bool
    let pushNotificationsEnabled: Bool
    let smsNotificationsEnabled: Bool
    let disconnectedAlertsEnabled: Bool
    let reconnectedAlertsEnabled: Bool

    init(
        userID: UUID,
        deviceID: String,
        monitoredPersonName: String,
        relationship: String?,
        monitorName: String,
        roomName: String,
        cautionInactivityMinutes: Int,
        criticalInactivityMinutes: Int,
        quietHoursStart: String,
        quietHoursEnd: String,
        cautionAlertsEnabled: Bool,
        criticalAlertsEnabled: Bool,
        pushNotificationsEnabled: Bool,
        smsNotificationsEnabled: Bool,
        disconnectedAlertsEnabled: Bool,
        reconnectedAlertsEnabled: Bool,
        timezone: String = TimeZone.current.identifier
    ) {
        self.userID = userID
        self.deviceID = deviceID
        self.monitoredPersonName = monitoredPersonName
        self.relationship = relationship
        self.monitorName = monitorName
        self.roomName = roomName
        self.cautionInactivityMinutes = cautionInactivityMinutes
        self.criticalInactivityMinutes = criticalInactivityMinutes
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.timezone = timezone
        self.cautionAlertsEnabled = cautionAlertsEnabled
        self.criticalAlertsEnabled = criticalAlertsEnabled
        self.pushNotificationsEnabled = pushNotificationsEnabled
        self.smsNotificationsEnabled = smsNotificationsEnabled
        self.disconnectedAlertsEnabled = disconnectedAlertsEnabled
        self.reconnectedAlertsEnabled = reconnectedAlertsEnabled
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case deviceID = "device_id"
        case monitoredPersonName = "monitored_person_name"
        case relationship
        case monitorName = "monitor_name"
        case roomName = "room_name"
        case cautionInactivityMinutes = "caution_inactivity_minutes"
        case criticalInactivityMinutes = "critical_inactivity_minutes"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
        case timezone
        case cautionAlertsEnabled = "caution_alerts_enabled"
        case criticalAlertsEnabled = "critical_alerts_enabled"
        case pushNotificationsEnabled = "push_notifications_enabled"
        case smsNotificationsEnabled = "sms_notifications_enabled"
        case disconnectedAlertsEnabled = "disconnected_alerts_enabled"
        case reconnectedAlertsEnabled = "reconnected_alerts_enabled"
    }
}
