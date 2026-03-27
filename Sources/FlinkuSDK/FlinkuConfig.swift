import Foundation

public struct FlinkuConfig {
    public let baseUrl: String
    public let apiKey: String?
    public let debug: Bool
    public let timeout: TimeInterval

    public init(
        baseUrl: String,
        apiKey: String? = nil,
        debug: Bool = false,
        timeout: TimeInterval = 5.0
    ) {
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.debug = debug
        self.timeout = timeout
    }

    /// Extracts subdomain from baseUrl
    /// e.g. https://yourapp.flku.dev → yourapp
    public var subdomain: String {
        guard let host = URL(string: baseUrl)?.host else { return "" }
        let parts = host.split(separator: ".")
        if parts.count >= 3 { return String(parts.first ?? "") }
        return host
    }

    /// Base URL for API calls (project subdomain stripped), e.g. `https://myapp.flku.dev` → `https://flku.dev`
    public var apiBaseUrl: String {
        guard let url = URL(string: baseUrl), let host = url.host else { return baseUrl }
        let parts = host.split(separator: ".")
        guard parts.count >= 3 else { return baseUrl }
        let apexHost = parts.dropFirst().joined(separator: ".")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "\(url.scheme ?? "https")://\(apexHost)"
        }
        components.host = apexHost
        return components.string ?? "\(url.scheme ?? "https")://\(apexHost)"
    }
}
