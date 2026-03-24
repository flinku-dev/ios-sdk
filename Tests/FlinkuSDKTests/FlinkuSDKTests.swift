import XCTest
@testable import FlinkuSDK

final class FlinkuSDKTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Flinku.reset()
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
        ]
        let link = FlinkuLink.from(json: json)
        XCTAssertTrue(link.matched)
        XCTAssertEqual(link.deepLink, "myapp://product/42")
        XCTAssertEqual(link.slug, "abc123")
        XCTAssertEqual(link.subdomain, "yourapp")
        XCTAssertEqual(link.title, "Product")
        XCTAssertEqual(link.projectId, "proj_1")
    }

    func testResetClearsMatchState() {
        UserDefaults.standard.set(true, forKey: "flinku_matched")
        UserDefaults.standard.set(Data(), forKey: "flinku_match_result")
        Flinku.reset()
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "flinku_matched"))
        XCTAssertNil(UserDefaults.standard.data(forKey: "flinku_match_result"))
    }
}
