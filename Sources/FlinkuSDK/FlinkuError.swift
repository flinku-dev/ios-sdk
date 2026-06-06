import Foundation

public enum FlinkuError: Error {
    case missingApiKey
    case invalidResponse
    case invalidURL
    case notConfigured
    case linkCreationFailed(String)
}

extension FlinkuError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .linkCreationFailed(let message):
            return message
        case .missingApiKey:
            return "Flinku API key is required for link creation."
        case .invalidResponse:
            return "Invalid response from Flinku API."
        case .invalidURL:
            return "Invalid Flinku API URL."
        case .notConfigured:
            return "Flinku is not configured. Call Flinku.configure() first."
        }
    }
}
