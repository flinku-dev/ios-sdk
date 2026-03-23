import Foundation

struct FlinkuHTTP {
    let baseURL: String
    let timeout: TimeInterval

    func post(
        path: String,
        body: [String: Any],
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let url = URL(string: baseURL + path) else {
            completion(.failure(FlinkuError.invalidURL))
            return
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(FlinkuError.noData))
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                completion(.success(json))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // Async/await version
    func post(path: String, body: [String: Any]) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            post(path: path, body: body) { result in
                continuation.resume(with: result)
            }
        }
    }
}

enum FlinkuError: Error {
    case notInitialized
    case invalidURL
    case noData
    case alreadyMatched
}
