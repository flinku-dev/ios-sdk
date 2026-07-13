import Foundation
#if os(iOS)
import UIKit
#endif

public class Flinku {
    private init() {}

    private static var config: FlinkuConfig?
    private static var secretKeyWarningShown = false
    private static var referralApiKeyWarningShown = false
    private static let matchedKey = "flinku_matched"
    private static let matchResultKey = "flinku_match_result"
    private static let userIdKey = "flinku_user_id"
    /// Survives `reset()`. Used by qualify after the pending referral is cleared.
    private static let referralProjectIdKey = "flinku_referral_project_id"
    private static let pendingReferralKeyPrefix = "flinku_pending_referral_"
    private static let pendingReferralTTL: TimeInterval = 30 * 24 * 60 * 60

    private static func referralTrackedKey(_ projectId: String, _ userId: String) -> String {
        "referral_tracked_\(projectId)_\(userId)"
    }

    private static func pendingReferralKey(_ projectId: String) -> String {
        "\(pendingReferralKeyPrefix)\(projectId)"
    }

    /// Configure Flinku with your project subdomain URL.
    /// Call once in AppDelegate or App struct before any match() call.
    ///
    /// [apiKey] accepts publishable keys (`flk_pk_`) or secret keys (`flk_live_`).
    /// Use your publishable key (`flk_pk_`) in apps. Never embed your secret key (`flk_live_`).
    ///
    /// Example:
    /// ```swift
    /// Flinku.configure(
    ///     baseUrl: "https://yourapp.flku.dev",
    ///     apiKey: "flk_pk_..."
    /// )
    /// ```
    public static func configure(baseUrl: String, apiKey: String? = nil, debug: Bool = false, timeout: TimeInterval = 5.0, readClipboard: Bool = true) {
        config = FlinkuConfig(baseUrl: baseUrl, apiKey: apiKey, debug: debug, timeout: timeout, readClipboard: readClipboard)
        if let apiKey = apiKey,
           apiKey.hasPrefix("flk_live_"),
           !secretKeyWarningShown {
            secretKeyWarningShown = true
            #if DEBUG
            print(
                "FLINKU WARNING: You are embedding a secret key (flk_live_) in your app. " +
                "Anyone can extract it and gain full access to your links. " +
                "Use your publishable key (flk_pk_) instead — find it in your project settings at app.flinku.dev."
            )
            #endif
        }
        // Retry a pending referral track if a userId was already stored (e.g. app relaunch).
        if let userId = UserDefaults.standard.string(forKey: userIdKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !userId.isEmpty {
            trackReferralInBackground(userId: userId)
        }
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

        if !result.matched {
            // Only read clipboard if server match failed AND readClipboard is enabled.
            // This prevents the iOS "paste permission" dialog on every install
            // when Universal Links handle attribution instead.
            guard config.readClipboard else {
                return result
            }
            #if os(iOS)
            let clipText = UIPasteboard.general.string ?? ""
            #else
            let clipText = ""
            #endif
            let baseUrl = config.baseUrl
            if !clipText.isEmpty && (clipText.contains(".flku.dev") || clipText.contains(baseUrl)) {
                #if os(iOS)
                UIPasteboard.general.string = ""
                #endif
                if let clipResult = await matchWithClipboardUrl(clipText) {
                    persistMatchResult(clipResult)
                    return clipResult
                }
            }
        } else {
            persistMatchResult(result)
        }

        return result
    }

    /// Match using a Flinku URL from the clipboard. Returns a link when matched, otherwise `nil`.
    static func matchWithClipboardUrl(_ url: String) async -> FlinkuLink? {
        guard let config = config else { return nil }
        return await FlinkuHTTP.matchWithClipboardUrl(url, config: config)
    }

    /// Create a short link. Requires `apiKey` in `configure`.
    public static func createLink(_ options: FlinkuLinkOptions, completion: @escaping (Result<FlinkuCreatedLink, Error>) -> Void) {
        guard let config = config else {
            DispatchQueue.main.async { completion(.failure(FlinkuError.notConfigured)) }
            return
        }
        guard let apiKey = config.apiKey else {
            DispatchQueue.main.async { completion(.failure(FlinkuError.missingApiKey)) }
            return
        }
        guard let url = URL(string: "\(config.apiBaseUrl)/api/links") else {
            DispatchQueue.main.async { completion(.failure(FlinkuError.invalidURL)) }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = config.timeout
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: options.toDict())
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let message = linkCreationErrorMessage(data: data, statusCode: statusCode)
                DispatchQueue.main.async { completion(.failure(FlinkuError.linkCreationFailed(message))) }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let link = FlinkuCreatedLink.from(json: json) else {
                DispatchQueue.main.async { completion(.failure(FlinkuError.invalidResponse)) }
                return
            }
            DispatchQueue.main.async { completion(.success(link)) }
        }.resume()
    }

    /// Create a short link optimistically: returns immediately with a locally
    /// generated slug and short URL, then registers the link on the server in
    /// the background. Requires `apiKey` in `configure`.
    public static func createLinkInstant(_ options: FlinkuLinkOptions) throws -> FlinkuCreatedLink {
        guard let config = config else {
            throw FlinkuError.notConfigured
        }
        guard config.apiKey != nil else {
            throw FlinkuError.missingApiKey
        }

        let slug = generateInstantSlug(from: options.title)
        let shortUrl = "https://\(config.subdomain).flku.dev/\(slug)"
        createLinkInstantInBackground(options: options, slug: slug, config: config)

        return FlinkuCreatedLink(
            id: "",
            slug: slug,
            shortUrl: shortUrl,
            deepLink: options.deepLink,
            params: options.params
        )
    }

    /// Create multiple short links in one request. Requires `apiKey` in `configure`.
    /// Sends `POST` to `/api/links/batch` with body `{"links":[...]}` and expects `{"links":[...]}` (or a top-level JSON array) in the response.
    public static func createLinks(_ options: [FlinkuLinkOptions], completion: @escaping (Result<[FlinkuCreatedLink], Error>) -> Void) {
        if options.isEmpty {
            DispatchQueue.main.async { completion(.success([])) }
            return
        }
        guard let config = config else {
            DispatchQueue.main.async { completion(.failure(FlinkuError.notConfigured)) }
            return
        }
        guard let apiKey = config.apiKey else {
            DispatchQueue.main.async { completion(.failure(FlinkuError.missingApiKey)) }
            return
        }
        guard let url = URL(string: "\(config.apiBaseUrl)/api/links/batch") else {
            DispatchQueue.main.async { completion(.failure(FlinkuError.invalidURL)) }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = config.timeout
        let payload: [String: Any] = ["links": options.map { $0.toDict() }]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let message = linkCreationErrorMessage(data: data, statusCode: statusCode)
                DispatchQueue.main.async { completion(.failure(FlinkuError.linkCreationFailed(message))) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(FlinkuError.invalidResponse)) }
                return
            }
            let parsed = try? JSONSerialization.jsonObject(with: data)
            let rawItems: [[String: Any]]
            if let json = parsed as? [String: Any], let links = json["links"] as? [[String: Any]] {
                rawItems = links
            } else if let arr = parsed as? [[String: Any]] {
                rawItems = arr
            } else {
                DispatchQueue.main.async { completion(.failure(FlinkuError.invalidResponse)) }
                return
            }
            guard rawItems.count == options.count else {
                DispatchQueue.main.async { completion(.failure(FlinkuError.invalidResponse)) }
                return
            }
            let links = rawItems.compactMap { FlinkuCreatedLink.from(json: $0) }
            guard links.count == rawItems.count else {
                DispatchQueue.main.async { completion(.failure(FlinkuError.invalidResponse)) }
                return
            }
            DispatchQueue.main.async { completion(.success(links)) }
        }.resume()
    }

    /// Stores userId locally and tracks a pending referral in the background.
    ///
    /// Returns immediately. Network work never blocks or throws to the caller.
    /// Reads the dedicated pending-referral record written at match time (not the
    /// match cache), so `reset()` cannot drop attribution.
    /// Tracks at most once per project+user (`referral_tracked_{projectId}_{userId}`).
    /// Requires `apiKey` in `configure`; otherwise logs a one-time warning and skips.
    public static func setUserId(_ userId: String) {
        let id = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty { return }
        warnMissingReferralApiKeyOnce()
        UserDefaults.standard.set(id, forKey: userIdKey)
        trackReferralInBackground(userId: id)
    }

    /// Marks the stored user as a qualified referral for an optional event.
    ///
    /// No-op if `setUserId` has not been called. Returns immediately.
    /// Requires `apiKey` in `configure`; otherwise logs a one-time warning and skips.
    public static func qualifyReferral(_ event: String? = nil) {
        warnMissingReferralApiKeyOnce()
        qualifyReferralInBackground(event: event)
    }

    private static func hasReferralApiKey() -> Bool {
        guard let apiKey = config?.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !apiKey.isEmpty
    }

    private static func warnMissingReferralApiKeyOnce() {
        if hasReferralApiKey() || referralApiKeyWarningShown { return }
        referralApiKeyWarningShown = true
        print("[Flinku] Referral tracking skipped: no apiKey configured. Pass apiKey: 'flk_pk_...' to Flinku.configure().")
    }

    /// Clears the cached match result so the next `match()` can hit the network again.
    /// Does **not** clear pending referral attribution or the stored user id.
    public static func reset() {
        UserDefaults.standard.removeObject(forKey: matchedKey)
        UserDefaults.standard.removeObject(forKey: matchResultKey)
    }

    private static func generateInstantSlug(from title: String) -> String {
        var base = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        base = base.replacingOccurrences(of: "[^a-z0-9\\s-]", with: "", options: .regularExpression)
        base = base.replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
        base = base.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if base.isEmpty {
            base = "link"
        }
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let suffix = String((0..<4).compactMap { _ in chars.randomElement() })
        return "\(base)-\(suffix)"
    }

    /// Writes `flinku_pending_referral_{projectId}` when the match has a referrerId.
    /// Independent of the match cache so it survives `reset()`.
    private static func persistPendingReferralIfNeeded(from result: FlinkuLink) {
        guard result.matched else { return }
        let projectId = (result.projectId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectId.isEmpty else { return }

        guard let params = result.params else { return }
        let referrerRaw = params["referrerId"] ?? params["referrer_id"]
        let referrerId = referrerRaw.map { "\($0)".trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        guard let referrerId = referrerId else { return }

        let labelRaw = params["referrerLabel"] ?? params["referrer_label"]
        let referrerLabel = labelRaw.map { "\($0)".trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }

        var linkId: String?
        if let raw = result.linkId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            linkId = raw
        } else if let raw = result.slug?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            linkId = raw
        }

        var value: [String: Any] = [
            "referrerId": referrerId,
            "matchedAt": Date().timeIntervalSince1970,
        ]
        if let referrerLabel = referrerLabel {
            value["referrerLabel"] = referrerLabel
        }
        if let linkId = linkId {
            value["linkId"] = linkId
        }

        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: pendingReferralKey(projectId))
        defaults.set(projectId, forKey: referralProjectIdKey)
    }

    private static func loadPendingReferral() -> (projectId: String, payload: [String: Any])? {
        let defaults = UserDefaults.standard
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix(pendingReferralKeyPrefix) {
            let projectId = String(key.dropFirst(pendingReferralKeyPrefix.count))
            guard !projectId.isEmpty,
                  let data = defaults.data(forKey: key),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let matchedAt: TimeInterval
            if let n = json["matchedAt"] as? TimeInterval {
                matchedAt = n
            } else if let n = json["matchedAt"] as? NSNumber {
                matchedAt = n.doubleValue
            } else {
                defaults.removeObject(forKey: key)
                continue
            }

            if Date().timeIntervalSince1970 - matchedAt > pendingReferralTTL {
                defaults.removeObject(forKey: key)
                continue
            }

            let referrerId = (json["referrerId"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !referrerId.isEmpty else {
                defaults.removeObject(forKey: key)
                continue
            }

            return (projectId, json)
        }
        return nil
    }

    private static func clearPendingReferral(projectId: String) {
        UserDefaults.standard.removeObject(forKey: pendingReferralKey(projectId))
    }

    private static func trackReferralInBackground(userId: String) {
        guard let config = config, hasReferralApiKey() else { return }
        guard let pending = loadPendingReferral() else { return }
        let projectId = pending.projectId
        let json = pending.payload

        let trackedKey = referralTrackedKey(projectId, userId)
        if UserDefaults.standard.bool(forKey: trackedKey) {
            clearPendingReferral(projectId: projectId)
            return
        }

        let referrerId = (json["referrerId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !referrerId.isEmpty else {
            clearPendingReferral(projectId: projectId)
            return
        }

        let referrerLabel = (json["referrerLabel"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let referrerLabelValue = (referrerLabel?.isEmpty == false) ? referrerLabel : nil
        let linkIdRaw = (json["linkId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let linkId = (linkIdRaw?.isEmpty == false) ? linkIdRaw : nil

        var body: [String: Any] = [
            "projectId": projectId,
            "referrerId": referrerId,
            "newUserId": userId,
        ]
        if let referrerLabelValue = referrerLabelValue {
            body["referrerLabel"] = referrerLabelValue
        }
        if let linkId = linkId {
            body["linkId"] = linkId
        }

        UserDefaults.standard.set(projectId, forKey: referralProjectIdKey)

        postReferralInBackground(
            path: "/api/referrals/track",
            body: body,
            config: config
        ) { success in
            guard success else { return }
            UserDefaults.standard.set(true, forKey: trackedKey)
            clearPendingReferral(projectId: projectId)
        }
    }

    private static func qualifyReferralInBackground(event: String?) {
        guard let config = config, hasReferralApiKey() else { return }
        guard let userId = UserDefaults.standard.string(forKey: userIdKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !userId.isEmpty else {
            return
        }

        var projectId = UserDefaults.standard.string(forKey: referralProjectIdKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if projectId.isEmpty, let pending = loadPendingReferral() {
            projectId = pending.projectId
        }
        // Fall back to match cache only if pending/project keys are absent.
        if projectId.isEmpty,
           let data = UserDefaults.standard.data(forKey: matchResultKey),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let fromMatch = (json["projectId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fromMatch.isEmpty {
            projectId = fromMatch
        }
        guard !projectId.isEmpty else { return }

        var body: [String: Any] = [
            "projectId": projectId,
            "newUserId": userId,
        ]
        if let event = event?.trimmingCharacters(in: .whitespacesAndNewlines), !event.isEmpty {
            body["event"] = event
        }

        postReferralInBackground(path: "/api/referrals/qualify", body: body, config: config)
    }

    private static func postReferralInBackground(
        path: String,
        body: [String: Any],
        config: FlinkuConfig,
        onComplete: ((Bool) -> Void)? = nil
    ) {
        guard let url = URL(string: "\(config.apiBaseUrl)\(path)") else {
            onComplete?(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            onComplete?(false)
            return
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = config.timeout
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            onComplete?(false)
            return
        }
        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                if config.debug {
                    print("[Flinku] referral \(path) error: \(error.localizedDescription)")
                }
                onComplete?(false)
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let ok = (200...299).contains(status)
            if !ok, config.debug {
                print("[Flinku] referral \(path) error: HTTP \(status)")
            }
            onComplete?(ok)
        }.resume()
    }

    private static func createLinkInstantInBackground(
        options: FlinkuLinkOptions,
        slug: String,
        config: FlinkuConfig
    ) {
        guard let apiKey = config.apiKey,
              let url = URL(string: "\(config.apiBaseUrl)/api/links") else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = config.timeout
        var payload = options.toDict()
        payload["slug"] = slug
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                if config.debug {
                    print("[Flinku] createLinkInstant background error: \(error.localizedDescription)")
                }
                return
            }
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                let message = linkCreationErrorMessage(data: data, statusCode: httpResponse.statusCode)
                if config.debug {
                    print("[Flinku] createLinkInstant background error: \(message)")
                }
            }
        }.resume()
    }

    private static func linkCreationErrorMessage(data: Data?, statusCode: Int) -> String {
        guard let data = data, !data.isEmpty else {
            return "Failed to create link: HTTP \(statusCode)"
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? String, !error.isEmpty {
                return error
            }
            if let message = json["message"] as? String, !message.isEmpty {
                return message
            }
        }
        return String(data: data, encoding: .utf8) ?? "Failed to create link: HTTP \(statusCode)"
    }

    private static func persistMatchResult(_ result: FlinkuLink) {
        guard result.matched else { return }
        UserDefaults.standard.set(true, forKey: matchedKey)
        var payload: [String: Any] = [
            "matched": true,
            "deepLink": result.deepLink ?? "",
            "slug": result.slug ?? "",
            "subdomain": result.subdomain ?? "",
            "title": result.title ?? "",
            "params": result.params ?? [:],
            "projectId": result.projectId ?? "",
            "matchType": result.matchType ?? "",
        ]
        if let linkId = result.linkId, !linkId.isEmpty {
            payload["linkId"] = linkId
        }
        if let json = try? JSONSerialization.data(withJSONObject: payload) {
            UserDefaults.standard.set(json, forKey: matchResultKey)
        }
        // Dedicated attribution record — survives reset().
        persistPendingReferralIfNeeded(from: result)
    }
}
