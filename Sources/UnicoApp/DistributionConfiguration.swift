import Foundation

enum DistributionConfiguration {
    /// The App Store build uses App Sandbox and only scans user-authorized locations.
    static var isAppStoreBuild: Bool {
        isAppStoreBuild(info: Bundle.main.infoDictionary ?? [:])
    }

    static func isAppStoreBuild(info: [String: Any]) -> Bool {
        info["UnicoAppStoreBuild"] as? Bool ?? false
    }
}
