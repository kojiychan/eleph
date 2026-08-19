import Foundation

struct AppConfiguration: Equatable {
    let supabaseURL: URL
    let supabaseAnonKey: String
    let monitorDeviceID: String
    let legalLinks: LegalLinks

    static func load(bundle: Bundle = .elephResourceBundle) -> AppConfiguration? {
        if let plistConfiguration = loadFromPlist(bundle: bundle) {
            return plistConfiguration
        }

        let environment = ProcessInfo.processInfo.environment
        guard let urlString = environment["SUPABASE_URL"],
              let key = environment["SUPABASE_ANON_KEY"],
              let url = URL(string: urlString),
              !key.isEmpty else {
            return nil
        }

        return AppConfiguration(
            supabaseURL: url,
            supabaseAnonKey: key,
            monitorDeviceID: environment["ELEPH_DEVICE_ID"] ?? "bathroom-monitor-001",
            legalLinks: LegalLinks(
                privacyPolicyURL: Self.url(from: environment["ELEPH_PRIVACY_POLICY_URL"]),
                termsURL: Self.url(from: environment["ELEPH_TERMS_URL"]),
                supportURL: Self.url(from: environment["ELEPH_SUPPORT_URL"]) ?? LegalLinks.defaultSupportURL,
                dataDeletionURL: Self.url(from: environment["ELEPH_DATA_DELETION_URL"]) ?? LegalLinks.defaultDataDeletionURL
            )
        )
    }

    private static func loadFromPlist(bundle: Bundle) -> AppConfiguration? {
        guard let url = bundle.url(forResource: "Supabase", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any],
              let urlString = dictionary["SUPABASE_URL"] as? String,
              let key = dictionary["SUPABASE_ANON_KEY"] as? String,
              let supabaseURL = URL(string: urlString),
              !key.isEmpty else {
            return nil
        }

        return AppConfiguration(
            supabaseURL: supabaseURL,
            supabaseAnonKey: key,
            monitorDeviceID: dictionary["ELEPH_DEVICE_ID"] as? String ?? "bathroom-monitor-001",
            legalLinks: LegalLinks(
                privacyPolicyURL: Self.url(from: dictionary["ELEPH_PRIVACY_POLICY_URL"] as? String),
                termsURL: Self.url(from: dictionary["ELEPH_TERMS_URL"] as? String),
                supportURL: Self.url(from: dictionary["ELEPH_SUPPORT_URL"] as? String) ?? LegalLinks.defaultSupportURL,
                dataDeletionURL: Self.url(from: dictionary["ELEPH_DATA_DELETION_URL"] as? String) ?? LegalLinks.defaultDataDeletionURL
            )
        )
    }

    private static func url(from value: String?) -> URL? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return URL(string: value)
    }
}

extension Bundle {
    static var elephResourceBundle: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }
}

struct LegalLinks: Equatable {
    let privacyPolicyURL: URL?
    let termsURL: URL?
    let supportURL: URL
    let dataDeletionURL: URL

    static let defaultSupportURL = URL(string: "mailto:kojiychan@gmail.com")!
    static let defaultDataDeletionURL = URL(string: "mailto:kojiychan@gmail.com?subject=Eleph%20Account%20and%20Data%20Deletion%20Request")!

    static let betaDefaults = LegalLinks(
        privacyPolicyURL: nil,
        termsURL: nil,
        supportURL: defaultSupportURL,
        dataDeletionURL: defaultDataDeletionURL
    )
}
