import Foundation

struct FlinkuStorage {
    private static let matchedKey = "flinku_matched"
    private static let launchedKey = "flinku_first_launch_done"
    private static let defaults = UserDefaults.standard

    static var hasMatched: Bool {
        get { defaults.bool(forKey: matchedKey) }
        set { defaults.set(newValue, forKey: matchedKey) }
    }

    static var hasLaunched: Bool {
        get { defaults.bool(forKey: launchedKey) }
        set { defaults.set(newValue, forKey: launchedKey) }
    }

    static func reset() {
        defaults.removeObject(forKey: matchedKey)
        defaults.removeObject(forKey: launchedKey)
    }
}
