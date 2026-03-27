import Foundation

public enum FlinkuError: Error {
    case missingApiKey
    case invalidResponse
    case invalidURL
    case notConfigured
}
