import Foundation

public struct FlinkuLink {
    public let matched: Bool
    public let deepLink: String?
    public let params: [String: Any]?
    public let slug: String?

    public static var noMatch: FlinkuLink {
        FlinkuLink(matched: false, deepLink: nil, params: nil, slug: nil)
    }

    init(matched: Bool, deepLink: String?, params: [String: Any]?, slug: String?) {
        self.matched = matched
        self.deepLink = deepLink
        self.params = params
        self.slug = slug
    }

    static func from(json: [String: Any]) -> FlinkuLink {
        let matched = json["matched"] as? Bool ?? false
        let deepLink = json["deepLink"] as? String
        let params = json["params"] as? [String: Any]
        let slug = json["slug"] as? String
        return FlinkuLink(matched: matched, deepLink: deepLink, params: params, slug: slug)
    }
}
