import Foundation

public struct FlinkuCreatedLink {
    public let id: String
    public let slug: String
    public let shortUrl: String
    public let deepLink: String?
    public let params: [String: String]?

    public init(id: String, slug: String, shortUrl: String, deepLink: String?, params: [String: String]?) {
        self.id = id
        self.slug = slug
        self.shortUrl = shortUrl
        self.deepLink = deepLink
        self.params = params
    }

    static func from(json: [String: Any]) -> FlinkuCreatedLink? {
        guard let id = json["id"] as? String,
              let slug = json["slug"] as? String,
              let shortUrl = json["shortUrl"] as? String else {
            return nil
        }
        return FlinkuCreatedLink(
            id: id,
            slug: slug,
            shortUrl: shortUrl,
            deepLink: json["deepLink"] as? String,
            params: json["params"] as? [String: String]
        )
    }
}
