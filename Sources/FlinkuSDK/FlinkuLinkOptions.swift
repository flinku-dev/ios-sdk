import Foundation

public struct FlinkuLinkOptions {
    public let title: String
    public var deepLink: String?
    public var params: [String: String]?
    public var slug: String?
    public var desktopUrl: String?
    public var utmSource: String?
    public var utmMedium: String?
    public var utmCampaign: String?
    public var utmContent: String?
    public var utmTerm: String?
    public var expiresAt: Date?
    public var maxClicks: Int?
    public var password: String?
    public var ogTitle: String?
    public var ogDescription: String?
    public var ogImageUrl: String?

    public init(title: String) {
        self.title = title
    }

    public func toDict() -> [String: Any] {
        var d: [String: Any] = ["title": title]
        if let v = deepLink { d["deepLink"] = v }
        if let v = params { d["params"] = v }
        if let v = slug { d["slug"] = v }
        if let v = desktopUrl { d["desktopUrl"] = v }
        if let v = utmSource { d["utmSource"] = v }
        if let v = utmMedium { d["utmMedium"] = v }
        if let v = utmCampaign { d["utmCampaign"] = v }
        if let v = utmContent { d["utmContent"] = v }
        if let v = utmTerm { d["utmTerm"] = v }
        if let v = expiresAt { d["expiresAt"] = ISO8601DateFormatter().string(from: v) }
        if let v = maxClicks { d["maxClicks"] = v }
        if let v = password { d["password"] = v }
        if let v = ogTitle { d["ogTitle"] = v }
        if let v = ogDescription { d["ogDescription"] = v }
        if let v = ogImageUrl { d["ogImageUrl"] = v }
        return d
    }
}
