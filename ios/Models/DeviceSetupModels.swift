import Foundation

struct SetupDevice: Identifiable, Hashable {
    let id: UUID
    var name: String
    var advertisedName: String
    var signalStrength: Int
    var serviceUUID: String?

    init(
        id: UUID = UUID(),
        name: String,
        advertisedName: String,
        signalStrength: Int,
        serviceUUID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.advertisedName = advertisedName
        self.signalStrength = signalStrength
        self.serviceUUID = serviceUUID
    }
}

enum SetupStatus: String, Codable, Hashable {
    case unknown
    case readyForProvisioning
    case alreadyProvisioned
    case busy
}

enum ProvisioningStatus: String, Codable, Hashable {
    case idle
    case receivingPayload
    case connectingToWiFi
    case connectedToWiFi
    case online
    case failed
}

struct DeviceQRCodePayload: Hashable {
    let deviceID: String
    let defaultDisplayName: String
    let claimToken: String
    let rawURL: URL
    let model: String?
    let hardwareSerial: String?
}

struct ProvisioningPayload: Codable, Hashable {
    let deviceID: String
    let displayName: String
    let claimToken: String
    let wifiSSID: String
    let wifiPassword: String
}

enum DeviceQRCodeParser {
    static func parse(_ rawValue: String) throws -> DeviceQRCodePayload {
        guard let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw AppServiceError.validation("QR code is not a valid Eleph device link.")
        }

        guard isAccepted(url) else {
            throw AppServiceError.validation("QR code is not an Eleph device setup link.")
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let deviceID = firstValue(named: ["device_id", "deviceID"], in: queryItems)
        let claimToken = firstValue(named: ["token", "claimToken", "claim_token"], in: queryItems)

        guard let deviceID, !deviceID.isEmpty else {
            throw AppServiceError.validation("QR code is missing the device ID.")
        }

        guard let claimToken, !claimToken.isEmpty else {
            throw AppServiceError.validation("QR code is missing the claim token.")
        }

        return DeviceQRCodePayload(
            deviceID: deviceID,
            defaultDisplayName: firstValue(named: ["name", "display_name", "displayName"], in: queryItems) ?? "Bathroom Monitor",
            claimToken: claimToken,
            rawURL: url,
            model: firstValue(named: ["model"], in: queryItems),
            hardwareSerial: firstValue(named: ["hardware_serial", "hardwareSerial", "serial"], in: queryItems)
        )
    }

    private static func isAccepted(_ url: URL) -> Bool {
        if url.scheme == "eleph", url.host == "device" {
            return true
        }

        guard url.scheme == "https", url.host == "eleph.app" else {
            return false
        }

        return url.path == "/device"
    }

    private static func firstValue(named names: [String], in queryItems: [URLQueryItem]) -> String? {
        for name in names {
            if let value = queryItems.first(where: { $0.name == name })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
