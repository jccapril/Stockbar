// Created by april on 2026/11/13.
import XCTest
@testable import Stockbar

@MainActor
final class RapidMoveTrackerTests: XCTestCase {
    func test_windowCooldownAndResetPreserveExistingAlerts() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var rule = PriceAlert(
            stockId: "sh600000",
            stockName: "示例",
            metric: .rapidRise,
            comparison: .atLeast,
            target: 2,
        )
        func quote(_ price: Double, _ seconds: Int) -> Quote {
            Quote(code: rule.stockId, price: price, change: 0, changePercent: 0, updateTime: "tick-\(seconds)")
        }
        var tracker = RapidMoveTracker()
        for second in stride(from: 0, to: 300, by: 30) {
            XCTAssertNil(tracker.observe(quote(100, second), at: start.addingTimeInterval(Double(second)), rule: rule))
        }
        XCTAssertEqual(
            try XCTUnwrap(tracker.observe(quote(102, 300), at: start.addingTimeInterval(300), rule: rule)),
            2,
            accuracy: 0.0001,
        )
        rule.triggeredAt = start.addingTimeInterval(300)
        XCTAssertNil(tracker.observe(quote(103, 330), at: start.addingTimeInterval(330), rule: rule))
        rule.triggeredAt = nil
        XCTAssertNil(tracker.observe(quote(103, 330), at: start.addingTimeInterval(335), rule: rule))
        XCTAssertNil(tracker.observe(quote(110, 600), at: start.addingTimeInterval(600), rule: rule))

        rule.metric = .rapidFall
        var fall = RapidMoveTracker()
        for second in stride(from: 0, to: 300, by: 30) {
            XCTAssertNil(fall.observe(quote(100, second), at: start.addingTimeInterval(Double(second)), rule: rule))
        }
        XCTAssertEqual(
            try XCTUnwrap(fall.observe(quote(98, 300), at: start.addingTimeInterval(300), rule: rule)),
            -2,
            accuracy: 0.0001,
        )
        XCTAssertNil(fall.observe(quote(0, 310), at: start.addingTimeInterval(310), rule: rule))
        XCTAssertNil(fall.observe(quote(90, 320), at: start.addingTimeInterval(320), rule: rule))

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(rule)) as? [String: Any])
        json["metric"] = "价格"
        json.removeValue(forKey: "windowMinutes")
        json.removeValue(forKey: "cooldownMinutes")
        let legacy = try JSONDecoder().decode(PriceAlert.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.windowMinutes, 5)
        XCTAssertEqual(legacy.cooldownMinutes, 10)
        XCTAssertTrue(legacy.matches(quote(100, 0)))
    }
}
