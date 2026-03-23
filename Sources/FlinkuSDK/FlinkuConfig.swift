import Foundation

public struct FlinkuConfig {
    public let apiKey: String
    public let baseURL: String
    public let debugMode: Bool
    public let matchTimeout: TimeInterval

    public init(
        apiKey: String,
        baseURL: String = "http://159.65.159.159:3001",
        debugMode: Bool = false,
        matchTimeout: TimeInterval = 10.0
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.debugMode = debugMode
        self.matchTimeout = matchTimeout
    }
}
