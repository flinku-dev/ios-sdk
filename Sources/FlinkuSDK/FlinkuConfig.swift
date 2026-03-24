import Foundation

public struct FlinkuConfig {
    public let baseUrl: String
    public let debug: Bool
    public let timeout: TimeInterval

    public init(
        baseUrl: String,
        debug: Bool = false,
        timeout: TimeInterval = 5.0
    ) {
        self.baseUrl = baseUrl
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
}
