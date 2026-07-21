import Foundation

/// Minimal task handle so referral POSTs can be mocked without `URLSession`.
protocol FlinkuNetworkTask {
    func resume()
}

/// HTTP transport used by Flinku (defaults to `URLSession.shared`).
protocol FlinkuNetworkClient: AnyObject {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func dataTask(
        with request: URLRequest,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> FlinkuNetworkTask
}

final class URLSessionNetworkClient: FlinkuNetworkClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    func dataTask(
        with request: URLRequest,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> FlinkuNetworkTask {
        URLSessionTaskBox(session.dataTask(with: request, completionHandler: completionHandler))
    }
}

private final class URLSessionTaskBox: FlinkuNetworkTask {
    private let task: URLSessionDataTask

    init(_ task: URLSessionDataTask) {
        self.task = task
    }

    func resume() {
        task.resume()
    }
}
