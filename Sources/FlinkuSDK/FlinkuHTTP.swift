import Foundation
#if os(iOS)
import UIKit
#endif

enum FlinkuHTTP {
    static func match(config: FlinkuConfig) async -> FlinkuLink {
        #if os(iOS)
        let userAgent = UIDevice.current.systemVersion
        #else
        let userAgent = "unknown"
        #endif

        let body: [String: Any] = [
            "subdomain": config.subdomain,
            "userAgent": userAgent,
        ]

        for attempt in 0..<2 {
            do {
                guard let url = URL(string: "\(config.baseUrl)/api/match") else {
                    return .notMatched
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                request.timeoutInterval = config.timeout

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    return .notMatched
                }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return .notMatched
                }
                return FlinkuLink.from(json: json)
            } catch {
                if attempt == 1 { return .notMatched }
            }
        }
        return .notMatched
    }
}
