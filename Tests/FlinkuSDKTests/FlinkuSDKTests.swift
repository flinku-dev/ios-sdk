import XCTest
@testable import FlinkuSDK

final class FlinkuSDKTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Flinku.resetForTesting()
    }

    func testConfigureSDK() {
        let config = FlinkuConfig(apiKey: "test_key", debugMode: true)
        Flinku.configure(config)
        XCTAssertNotNil(config)
    }

    func testFlinkuLinkNoMatch() {
        let link = FlinkuLink.noMatch
        XCTAssertFalse(link.matched)
        XCTAssertNil(link.deepLink)
        XCTAssertNil(link.slug)
    }

    func testFlinkuLinkFromJSON() {
        let json: [String: Any] = [
            "matched": true,
            "deepLink": "myapp://product/42",
            "slug": "abc123",
            "params": ["id": "42"]
        ]
        let link = FlinkuLink.from(json: json)
        XCTAssertTrue(link.matched)
        XCTAssertEqual(link.deepLink, "myapp://product/42")
        XCTAssertEqual(link.slug, "abc123")
    }

    func testStorageReset() {
        FlinkuStorage.hasMatched = true
        FlinkuStorage.hasLaunched = true
        FlinkuStorage.reset()
        XCTAssertFalse(FlinkuStorage.hasMatched)
        XCTAssertFalse(FlinkuStorage.hasLaunched)
    }
}
