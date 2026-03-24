import Foundation

public class Flinku {
    private init() {}

    private static var config: FlinkuConfig?
    private static let matchedKey = "flinku_matched"
    private static let matchResultKey = "flinku_match_result"

    /// Configure Flinku with your project subdomain URL.
    /// Call once in AppDelegate or App struct before any match() call.
    ///
    /// Example:
    /// ```swift
    /// Flinku.configure(baseUrl: "https://yourapp.flku.dev")
    /// ```
    public static func configure(baseUrl: String, debug: Bool = false, timeout: TimeInterval = 5.0) {
        config = FlinkuConfig(baseUrl: baseUrl, debug: debug, timeout: timeout)
    }

    /// Returns true if match() has already found a match.
    /// Prevents double-matching across app launches.
    public static var hasMatched: Bool {
        UserDefaults.standard.bool(forKey: matchedKey)
    }

    /// Match the current device to a previously clicked Flinku link.
    /// Call once on app launch — typically in the splash screen or onAppear.
    public static func match() async -> FlinkuLink {
        guard let config = config else {
            print("[Flinku] Not configured. Call Flinku.configure() first.")
            return .notMatched
        }

        if UserDefaults.standard.bool(forKey: matchedKey) {
            if let data = UserDefaults.standard.data(forKey: matchResultKey),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return FlinkuLink.from(json: json)
            }
            return .notMatched
        }

        let result = await FlinkuHTTP.match(config: config)

        if result.matched {
            UserDefaults.standard.set(true, forKey: matchedKey)
            if let json = try? JSONSerialization.data(withJSONObject: [
                "matched": true,
                "deepLink": result.deepLink ?? "",
                "slug": result.slug ?? "",
                "subdomain": result.subdomain ?? "",
                "title": result.title ?? "",
                "params": result.params ?? [:],
                "projectId": result.projectId ?? "",
            ]) {
                UserDefaults.standard.set(json, forKey: matchResultKey)
            }
        }
        return result
    }

    /// Reset stored match result. Use only during development/testing.
    public static func reset() {
        UserDefaults.standard.removeObject(forKey: matchedKey)
        UserDefaults.standard.removeObject(forKey: matchResultKey)
    }
}
