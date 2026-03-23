import Foundation
#if os(iOS)
import UIKit
#endif

public final class Flinku {
    private static var config: FlinkuConfig?
    private static var http: FlinkuHTTP?

    private init() {}

    // MARK: - Configure
    /// Call this in AppDelegate didFinishLaunchingWithOptions or App init
    public static func configure(_ config: FlinkuConfig) {
        self.config = config
        self.http = FlinkuHTTP(baseURL: config.baseURL, timeout: config.matchTimeout)
        FlinkuLogger.debugMode = config.debugMode
        FlinkuLogger.log("SDK configured with baseURL: \(config.baseURL)")
    }

    // MARK: - Match
    /// Call once on app launch to check for deferred deep link
    /// Uses async/await — requires iOS 15+ or Xcode concurrency back-deployment
    @discardableResult
    public static func match() async -> FlinkuLink {
        guard let config = config, let http = http else {
            FlinkuLogger.error("SDK not initialized. Call Flinku.configure() first.")
            return .noMatch
        }

        // Already matched before — never match twice
        guard !FlinkuStorage.hasMatched else {
            FlinkuLogger.log("Already matched previously, skipping.")
            return .noMatch
        }

        // Only match on first launch
        guard !FlinkuStorage.hasLaunched else {
            FlinkuLogger.log("Not first launch, skipping match.")
            return .noMatch
        }

        FlinkuLogger.log("Attempting deferred deep link match...")

        #if os(iOS)
        let userAgent = "FlinkuSDK/iOS/\(UIDevice.current.systemVersion)"
        #else
        let userAgent = "FlinkuSDK/iOS"
        #endif

        let body: [String: Any] = [
            "apiKey": config.apiKey,
            "deviceInfo": [
                "platform": "ios",
                "userAgent": userAgent,
                "timestamp": Int(Date().timeIntervalSince1970 * 1000)
            ]
        ]

        do {
            let response = try await http.post(path: "/api/match", body: body)
            let link = FlinkuLink.from(json: response)

            FlinkuStorage.hasLaunched = true

            if link.matched {
                FlinkuStorage.hasMatched = true
                FlinkuLogger.log("Match found: \(link.deepLink ?? "none")")
            } else {
                FlinkuLogger.log("No match found.")
            }

            return link
        } catch {
            FlinkuLogger.error("Match failed: \(error.localizedDescription)")
            FlinkuStorage.hasLaunched = true
            return .noMatch
        }
    }

    // MARK: - Match with completion handler (for older codebases)
    public static func match(completion: @escaping (FlinkuLink) -> Void) {
        Task {
            let link = await match()
            DispatchQueue.main.async {
                completion(link)
            }
        }
    }

    // MARK: - Debug reset
    /// Only use during development to reset match state
    public static func resetForTesting() {
        FlinkuStorage.reset()
        FlinkuLogger.log("SDK state reset for testing.")
    }
}
