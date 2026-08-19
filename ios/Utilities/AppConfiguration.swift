import Foundation

struct AppConfiguration: Equatable {
    let supabaseURL: URL
    let supabaseAnonKey: String
    let monitorDeviceID: String

    static func load(bundle: Bundle = .module) -> AppConfiguration? {
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
            monitorDeviceID: environment["ELEPH_DEVICE_ID"] ?? "bathroom-monitor-001"
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
            monitorDeviceID: dictionary["ELEPH_DEVICE_ID"] as? String ?? "bathroom-monitor-001"
        )
    }
}
