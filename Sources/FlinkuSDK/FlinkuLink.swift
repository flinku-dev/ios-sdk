import Foundation

public struct FlinkuLink {
    public let matched: Bool
    public let deepLink: String?
    public let slug: String?
    public let subdomain: String?
    public let title: String?
    public let params: [String: Any]?
    public let clickedAt: Date?
    public let projectId: String?

    public static let notMatched = FlinkuLink(
        matched: false,
        deepLink: nil,
        slug: nil,
        subdomain: nil,
        title: nil,
        params: nil,
        clickedAt: nil,
        projectId: nil
    )

    static func from(json: [String: Any]) -> FlinkuLink {
        let matched = json["matched"] as? Bool ?? false
        var clickedAt: Date? = nil
        if let clickedAtStr = json["clickedAt"] as? String {
            let formatter = ISO8601DateFormatter()
            clickedAt = formatter.date(from: clickedAtStr)
        }
        return FlinkuLink(
            matched: matched,
            deepLink: json["deepLink"] as? String,
            slug: json["slug"] as? String,
            subdomain: json["subdomain"] as? String,
            title: json["title"] as? String,
            params: json["params"] as? [String: Any],
            clickedAt: clickedAt,
            projectId: json["projectId"] as? String
        )
    }
}
