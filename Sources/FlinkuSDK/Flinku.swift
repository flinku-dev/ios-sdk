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
    public static func configure(baseUrl: String, apiKey: String? = nil, debug: Bool = false, timeout: TimeInterval = 5.0) {
        config = FlinkuConfig(baseUrl: baseUrl, apiKey: apiKey, debug: debug, timeout: timeout)
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
                DispatchQueue.main.async { completion(.failure(FlinkuError.invalidResponse)) }
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
                DispatchQueue.main.async { completion(.failure(FlinkuError.invalidResponse)) }
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

    /// Reset stored match result. Use only during development/testing.
    public static func reset() {
        UserDefaults.standard.removeObject(forKey: matchedKey)
        UserDefaults.standard.removeObject(forKey: matchResultKey)
    }
}
