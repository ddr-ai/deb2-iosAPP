import XCTest
@testable import Deb2IPA

final class EngineTests: XCTestCase {
    func testCoreVersionIsExposed() {
        XCTAssertFalse(ConvertEngine.coreVersion.isEmpty)
    }

    func testPlanOptionsRoundTrip() throws {
        let plan = PlanOptions(bundleId: "com.ddrai.wget", displayName: "wget", version: "1.2.3")
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(PlanOptions.self, from: data)
        XCTAssertEqual(decoded, plan)
    }
}
