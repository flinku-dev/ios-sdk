import XCTest
@testable import FlinkuSDK

// MARK: - Mocks

final class MockKeyValueStore: FlinkuKeyValueStore {
    private var values: [String: Any] = [:]

    func bool(forKey key: String) -> Bool {
        (values[key] as? Bool) ?? false
    }

    func set(_ value: Bool, forKey key: String) {
        values[key] = value
    }

    func string(forKey key: String) -> String? {
        values[key] as? String
    }

    func set(_ value: String?, forKey key: String) {
        if let value {
            values[key] = value
        } else {
            values.removeValue(forKey: key)
        }
    }

    func data(forKey key: String) -> Data? {
        values[key] as? Data
    }

    func set(_ value: Data?, forKey key: String) {
        if let value {
            values[key] = value
        } else {
            values.removeValue(forKey: key)
        }
    }

    func removeObject(forKey key: String) {
        values.removeValue(forKey: key)
    }

    func dictionaryRepresentation() -> [String: Any] {
        values
    }

    func pendingReferralJSON(projectId: String) -> [String: Any]? {
        guard let data = data(forKey: "flinku_pending_referral_\(projectId)"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    func hasPendingReferral(projectId: String) -> Bool {
        data(forKey: "flinku_pending_referral_\(projectId)") != nil
    }
}

final class MockNetworkClient: FlinkuNetworkClient {
    struct RecordedRequest {
        let url: URL
        let method: String
        let headers: [String: String]
        let body: [String: Any]?
    }

    private(set) var recorded: [RecordedRequest] = []
    /// Path suffix → canned async `data(for:)` response (match).
    var asyncResponses: [String: (Data, Int)] = [:]
    /// Path suffix → canned dataTask response (referrals).
    var taskResponses: [String: (Data?, Int, Error?)] = [:]
    /// Force network failure for dataTask paths.
    var taskError: Error?
    /// When true, every dataTask fails with `taskError` or a generic URLError.
    var failAllTasks = false

    func reset() {
        recorded.removeAll()
        asyncResponses.removeAll()
        taskResponses.removeAll()
        taskError = nil
        failAllTasks = false
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        record(request)
        let path = request.url?.path ?? ""
        if let canned = asyncResponses.first(where: { path.hasSuffix($0.key) })?.value {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: canned.1,
                httpVersion: nil,
                headerFields: nil
            )!
            return (canned.0, response)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(), response)
    }

    func dataTask(
        with request: URLRequest,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> FlinkuNetworkTask {
        record(request)
        let path = request.url?.path ?? ""
        let canned = taskResponses.first(where: { path.hasSuffix($0.key) })?.value
        let error: Error? = failAllTasks ? (taskError ?? URLError(.notConnectedToInternet)) : canned?.2
        let status = canned?.1 ?? (error == nil ? 200 : 0)
        let data = canned?.0
        let url = request.url ?? URL(string: "https://flku.dev")!
        return MockNetworkTask {
            if let error {
                completionHandler(nil, nil, error)
                return
            }
            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )
            completionHandler(data, response, nil)
        }
    }

    private func record(_ request: URLRequest) {
        var headers: [String: String] = [:]
        request.allHTTPHeaderFields?.forEach { headers[$0.key] = $0.value }
        var body: [String: Any]?
        if let httpBody = request.httpBody,
           let json = try? JSONSerialization.jsonObject(with: httpBody) as? [String: Any] {
            body = json
        }
        recorded.append(
            RecordedRequest(
                url: request.url!,
                method: request.httpMethod ?? "GET",
                headers: headers,
                body: body
            )
        )
    }

    func requests(matchingPath path: String) -> [RecordedRequest] {
        recorded.filter { $0.url.path.hasSuffix(path) || $0.url.path == path }
    }
}

private final class MockNetworkTask: FlinkuNetworkTask {
    private let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    func resume() { block() }
}

// MARK: - Referral lifecycle tests

final class FlinkuReferralLifecycleTests: XCTestCase {
    private var store: MockKeyValueStore!
    private var network: MockNetworkClient!
    private var logs: [String] = []

    private let projectId = "proj_test_1"
    private let apiKey = "flk_pk_test_key"
    private let baseUrl = "https://yourapp.flku.dev"

    override func setUp() {
        super.setUp()
        Flinku.resetForTesting()
        store = MockKeyValueStore()
        network = MockNetworkClient()
        logs = []
        Flinku.store = store
        Flinku.network = network
        Flinku.logSink = { [weak self] message in
            self?.logs.append(message)
        }
    }

    override func tearDown() {
        Flinku.resetForTesting()
        super.tearDown()
    }

    // 1. match() with referrerId → pending written with correct fields
    func testMatchWithReferrerIdWritesPendingReferral() async {
        stubMatchJSON([
            "matched": true,
            "deepLink": "myapp://home",
            "slug": "ref-slug",
            "linkId": "link_abc",
            "subdomain": "yourapp",
            "title": "Invite",
            "projectId": projectId,
            "matchType": "fingerprint",
            "params": [
                "referrerId": "user_referrer_1",
                "referrerLabel": "Alice",
            ],
        ])
        Flinku.configure(baseUrl: baseUrl, apiKey: apiKey, readClipboard: false)

        let link = await Flinku.match()

        XCTAssertTrue(link.matched)
        guard let pending = store.pendingReferralJSON(projectId: projectId) else {
            return XCTFail("Expected pending referral record for project \(projectId)")
        }
        XCTAssertEqual(pending["referrerId"] as? String, "user_referrer_1")
        XCTAssertEqual(pending["referrerLabel"] as? String, "Alice")
        XCTAssertEqual(pending["linkId"] as? String, "link_abc")
        XCTAssertNotNil(pending["matchedAt"] as? TimeInterval)
        XCTAssertEqual(store.string(forKey: "flinku_referral_project_id"), projectId)
    }

    // 2. match() without referrerId → no pending
    func testMatchWithoutReferrerIdDoesNotWritePending() async {
        stubMatchJSON([
            "matched": true,
            "deepLink": "myapp://home",
            "slug": "plain-slug",
            "linkId": "link_plain",
            "projectId": projectId,
            "params": ["campaign": "summer"],
        ])
        Flinku.configure(baseUrl: baseUrl, apiKey: apiKey, readClipboard: false)

        let link = await Flinku.match()

        XCTAssertTrue(link.matched)
        XCTAssertFalse(store.hasPendingReferral(projectId: projectId))
        XCTAssertNil(store.string(forKey: "flinku_referral_project_id"))
    }

    // 3. reset() after match with referrerId → pending still exists
    func testResetKeepsPendingReferral() async {
        stubMatchJSON(matchedWithReferrerJSON())
        Flinku.configure(baseUrl: baseUrl, apiKey: apiKey, readClipboard: false)
        _ = await Flinku.match()
        XCTAssertTrue(store.hasPendingReferral(projectId: projectId))
        XCTAssertTrue(store.bool(forKey: "flinku_matched"))

        Flinku.reset()

        XCTAssertFalse(store.bool(forKey: "flinku_matched"))
        XCTAssertNil(store.data(forKey: "flinku_match_result"))
        guard let pending = store.pendingReferralJSON(projectId: projectId) else {
            return XCTFail("Pending referral must survive reset()")
        }
        XCTAssertEqual(pending["referrerId"] as? String, "user_referrer_1")
        XCTAssertEqual(pending["referrerLabel"] as? String, "Alice")
        XCTAssertEqual(pending["linkId"] as? String, "link_abc")
    }

    // 4. setUserId with pending → POST track with correct body + Bearer
    func testSetUserIdPostsTrackWithCorrectBodyAndBearer() async {
        stubMatchJSON(matchedWithReferrerJSON())
        network.taskResponses["/api/referrals/track"] = (Data(), 200, nil)
        Flinku.configure(baseUrl: baseUrl, apiKey: apiKey, readClipboard: false)
        _ = await Flinku.match()

        Flinku.setUserId("new_user_42")

        let tracks = network.requests(matchingPath: "/api/referrals/track")
        XCTAssertEqual(tracks.count, 1)
        let req = tracks[0]
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.url.host, "flku.dev")
        XCTAssertEqual(req.headers["Authorization"], "Bearer \(apiKey)")
        XCTAssertEqual(req.body?["projectId"] as? String, projectId)
        XCTAssertEqual(req.body?["referrerId"] as? String, "user_referrer_1")
        XCTAssertEqual(req.body?["newUserId"] as? String, "new_user_42")
        XCTAssertEqual(req.body?["referrerLabel"] as? String, "Alice")
        XCTAssertEqual(req.body?["linkId"] as? String, "link_abc")
    }

    // 5. setUserId 2xx → tracked flag set, pending cleared
    func testSetUserIdSuccessSetsTrackedFlagAndClearsPending() async {
        stubMatchJSON(matchedWithReferrerJSON())
        network.taskResponses["/api/referrals/track"] = (Data(), 201, nil)
        Flinku.configure(baseUrl: baseUrl, apiKey: apiKey, readClipboard: false)
        _ = await Flinku.match()
        XCTAssertTrue(store.hasPendingReferral(projectId: projectId))

        Flinku.setUserId("new_user_42")

        XCTAssertTrue(store.bool(forKey: "referral_tracked_\(projectId)_new_user_42"))
        XCTAssertFalse(store.hasPendingReferral(projectId: projectId))
    }

    // 6. setUserId network failure → pending NOT cleared
    func testSetUserIdNetworkFailureKeepsPending() async {
        stubMatchJSON(matchedWithReferrerJSON())
        network.failAllTasks = true
        network.taskError = URLError(.timedOut)
        Flinku.configure(baseUrl: baseUrl, apiKey: apiKey, readClipboard: false)
        _ = await Flinku.match()

        Flinku.setUserId("new_user_42")

        XCTAssertEqual(network.requests(matchingPath: "/api/referrals/track").count, 1)
        XCTAssertTrue(store.hasPendingReferral(projectId: projectId))
        XCTAssertFalse(store.bool(forKey: "referral_tracked_\(projectId)_new_user_42"))
    }

    // 7. setUserId twice after success → only one POST
    func testSetUserIdTwiceAfterSuccessPostsOnlyOnce() async {
        stubMatchJSON(matchedWithReferrerJSON())
        network.taskResponses["/api/referrals/track"] = (Data(), 200, nil)
        Flinku.configure(baseUrl: baseUrl, apiKey: apiKey, readClipboard: false)
        _ = await Flinku.match()

        Flinku.setUserId("new_user_42")
        XCTAssertEqual(network.requests(matchingPath: "/api/referrals/track").count, 1)
        XCTAssertFalse(store.hasPendingReferral(projectId: projectId))

        // Second call: no pending + tracked flag → no second POST
        Flinku.setUserId("new_user_42")
        XCTAssertEqual(network.requests(matchingPath: "/api/referrals/track").count, 1)
    }

    // 8. setUserId with no apiKey → no network, warning once
    func testSetUserIdWithoutApiKeySkipsNetworkAndWarnsOnce() async {
        stubMatchJSON(matchedWithReferrerJSON())
        Flinku.configure(baseUrl: baseUrl, apiKey: nil, readClipboard: false)
        _ = await Flinku.match()
        XCTAssertTrue(store.hasPendingReferral(projectId: projectId))

        Flinku.setUserId("new_user_42")
        Flinku.setUserId("new_user_42")

        XCTAssertTrue(network.requests(matchingPath: "/api/referrals/track").isEmpty)
        XCTAssertTrue(store.hasPendingReferral(projectId: projectId))
        let warnings = logs.filter { $0.contains("no apiKey configured") }
        XCTAssertEqual(warnings.count, 1)
        XCTAssertEqual(store.string(forKey: "flinku_user_id"), "new_user_42")
    }

    // 9. configure later with stored userId + pending → retry POST
    func testConfigureWithStoredUserIdRetriesTrack() {
        // Simulate prior launch: pending + userId already on disk, no config yet.
        writePending(
            projectId: projectId,
            referrerId: "user_referrer_1",
            referrerLabel: "Alice",
            linkId: "link_abc",
            matchedAt: Date().timeIntervalSince1970
        )
        store.set("returning_user", forKey: "flinku_user_id")
        network.taskResponses["/api/referrals/track"] = (Data(), 200, nil)

        Flinku.configure(baseUrl: baseUrl, apiKey: apiKey, readClipboard: false)

        let tracks = network.requests(matchingPath: "/api/referrals/track")
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].body?["newUserId"] as? String, "returning_user")
        XCTAssertEqual(tracks[0].body?["referrerId"] as? String, "user_referrer_1")
        XCTAssertEqual(tracks[0].headers["Authorization"], "Bearer \(apiKey)")
        XCTAssertTrue(store.bool(forKey: "referral_tracked_\(projectId)_returning_user"))
        XCTAssertFalse(store.hasPendingReferral(projectId: projectId))
    }

    // 10. pending older than 30 days → dropped, no POST
    func testStalePendingReferralIsDroppedWithoutPost() {
        let thirtyOneDaysAgo = Date().timeIntervalSince1970 - (31 * 24 * 60 * 60)
        writePending(
            projectId: projectId,
            referrerId: "user_referrer_1",
            referrerLabel: "Alice",
            linkId: "link_abc",
            matchedAt: thirtyOneDaysAgo
        )
        store.set("returning_user", forKey: "flinku_user_id")
        network.taskResponses["/api/referrals/track"] = (Data(), 200, nil)

        Flinku.configure(baseUrl: baseUrl, apiKey: apiKey, readClipboard: false)

        XCTAssertTrue(network.requests(matchingPath: "/api/referrals/track").isEmpty)
        XCTAssertFalse(store.hasPendingReferral(projectId: projectId))
        XCTAssertFalse(store.bool(forKey: "referral_tracked_\(projectId)_returning_user"))
    }

    // 11. qualifyReferral("first_meal_logged") → POST qualify correct body
    func testQualifyReferralPostsCorrectBody() async {
        stubMatchJSON(matchedWithReferrerJSON())
        network.taskResponses["/api/referrals/track"] = (Data(), 200, nil)
        network.taskResponses["/api/referrals/qualify"] = (Data(), 200, nil)
        Flinku.configure(baseUrl: baseUrl, apiKey: apiKey, readClipboard: false)
        _ = await Flinku.match()
        Flinku.setUserId("new_user_42")

        Flinku.qualifyReferral("first_meal_logged")

        let qualifies = network.requests(matchingPath: "/api/referrals/qualify")
        XCTAssertEqual(qualifies.count, 1)
        let req = qualifies[0]
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.url.path, "/api/referrals/qualify")
        XCTAssertEqual(req.headers["Authorization"], "Bearer \(apiKey)")
        XCTAssertEqual(req.body?["projectId"] as? String, projectId)
        XCTAssertEqual(req.body?["newUserId"] as? String, "new_user_42")
        XCTAssertEqual(req.body?["event"] as? String, "first_meal_logged")
    }

    // 12. qualifyReferral with no userId → no call
    func testQualifyReferralWithoutUserIdDoesNotCallNetwork() async {
        stubMatchJSON(matchedWithReferrerJSON())
        network.taskResponses["/api/referrals/qualify"] = (Data(), 200, nil)
        Flinku.configure(baseUrl: baseUrl, apiKey: apiKey, readClipboard: false)
        _ = await Flinku.match()
        // project id present from pending, but no setUserId
        XCTAssertNil(store.string(forKey: "flinku_user_id"))

        Flinku.qualifyReferral("first_meal_logged")

        XCTAssertTrue(network.requests(matchingPath: "/api/referrals/qualify").isEmpty)
    }

    // MARK: - Helpers

    private func stubMatchJSON(_ json: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: json)
        network.asyncResponses["/api/match"] = (data, 200)
    }

    private func matchedWithReferrerJSON() -> [String: Any] {
        [
            "matched": true,
            "deepLink": "myapp://home",
            "slug": "ref-slug",
            "linkId": "link_abc",
            "subdomain": "yourapp",
            "title": "Invite",
            "projectId": projectId,
            "matchType": "fingerprint",
            "params": [
                "referrerId": "user_referrer_1",
                "referrerLabel": "Alice",
            ],
        ]
    }

    private func writePending(
        projectId: String,
        referrerId: String,
        referrerLabel: String,
        linkId: String,
        matchedAt: TimeInterval
    ) {
        let value: [String: Any] = [
            "referrerId": referrerId,
            "referrerLabel": referrerLabel,
            "linkId": linkId,
            "matchedAt": matchedAt,
        ]
        let data = try! JSONSerialization.data(withJSONObject: value)
        store.set(data, forKey: "flinku_pending_referral_\(projectId)")
        store.set(projectId, forKey: "flinku_referral_project_id")
    }
}

// MARK: - Existing smoke tests (updated for injectable store)

final class FlinkuSDKTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Flinku.resetForTesting()
        Flinku.reset()
    }

    override func tearDown() {
        Flinku.resetForTesting()
        super.tearDown()
    }

    func testConfigureSDK() {
        Flinku.configure(baseUrl: "https://yourapp.flku.dev", debug: true)
        let config = FlinkuConfig(baseUrl: "https://yourapp.flku.dev", debug: true)
        XCTAssertEqual(config.subdomain, "yourapp")
    }

    func testSubdomainFromBaseUrl() {
        let config = FlinkuConfig(baseUrl: "https://yourapp.flku.dev")
        XCTAssertEqual(config.subdomain, "yourapp")
    }

    func testApiBaseUrlStripsSubdomain() {
        let config = FlinkuConfig(baseUrl: "https://myapp.flku.dev")
        XCTAssertEqual(config.apiBaseUrl, "https://flku.dev")
    }

    func testLinkOptionsToDict() {
        var opts = FlinkuLinkOptions(title: "Hello")
        opts.deepLink = "myapp://x"
        opts.params = ["a": "b"]
        let d = opts.toDict()
        XCTAssertEqual(d["title"] as? String, "Hello")
        XCTAssertEqual(d["deepLink"] as? String, "myapp://x")
        XCTAssertEqual((d["params"] as? [String: String])?["a"], "b")
    }

    func testFlinkuCreatedLinkFromJSON() {
        let json: [String: Any] = [
            "id": "1",
            "slug": "abc",
            "shortUrl": "https://flku.dev/abc",
            "deepLink": "myapp://x",
            "params": ["k": "v"],
        ]
        let link = FlinkuCreatedLink.from(json: json)
        XCTAssertEqual(link?.id, "1")
        XCTAssertEqual(link?.slug, "abc")
        XCTAssertEqual(link?.shortUrl, "https://flku.dev/abc")
        XCTAssertEqual(link?.params?["k"], "v")
    }

    func testFlinkuLinkNotMatched() {
        let link = FlinkuLink.notMatched
        XCTAssertFalse(link.matched)
        XCTAssertNil(link.deepLink)
        XCTAssertNil(link.slug)
    }

    func testFlinkuLinkFromJSON() {
        let json: [String: Any] = [
            "matched": true,
            "deepLink": "myapp://product/42",
            "slug": "abc123",
            "subdomain": "yourapp",
            "title": "Product",
            "params": ["id": "42"],
            "projectId": "proj_1",
            "matchType": "fingerprint",
        ]
        let link = FlinkuLink.from(json: json)
        XCTAssertTrue(link.matched)
        XCTAssertEqual(link.deepLink, "myapp://product/42")
        XCTAssertEqual(link.slug, "abc123")
        XCTAssertEqual(link.subdomain, "yourapp")
        XCTAssertEqual(link.title, "Product")
        XCTAssertEqual(link.projectId, "proj_1")
        XCTAssertEqual(link.matchType, "fingerprint")
    }

    func testResetClearsMatchState() {
        let store = MockKeyValueStore()
        Flinku.store = store
        store.set(true, forKey: "flinku_matched")
        store.set(Data(), forKey: "flinku_match_result")
        Flinku.reset()
        XCTAssertFalse(store.bool(forKey: "flinku_matched"))
        XCTAssertNil(store.data(forKey: "flinku_match_result"))
    }
}
