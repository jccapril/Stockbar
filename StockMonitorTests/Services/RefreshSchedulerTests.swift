import XCTest
@testable import Stockbar

final class RefreshSchedulerTests: XCTestCase {

    private func makeDate(weekday: Int, hour: Int, minute: Int = 0) -> Date {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        c.weekday = weekday
        c.hour    = hour
        c.minute  = minute
        c.second  = 0
        return cal.date(from: c) ?? Date()
    }

    // A股上午开盘
    func test_aStock_morningSession_isTrading() {
        let d = makeDate(weekday: 2, hour: 10, minute: 0)  // 周一 10:00
        XCTAssertTrue(RefreshScheduler.isTradingHour(at: d))
    }

    // A股下午开盘
    func test_aStock_afternoonSession_isTrading() {
        let d = makeDate(weekday: 2, hour: 14, minute: 0)  // 周一 14:00
        XCTAssertTrue(RefreshScheduler.isTradingHour(at: d))
    }

    // 午休期间不因海外市场交易而继续刷新。
    func test_aStock_lunchBreak_notTrading() {
        let d = makeDate(weekday: 2, hour: 12, minute: 0)  // 周一 12:00
        XCTAssertFalse(RefreshScheduler.isTradingHour(at: d))
    }

    // 周末不交易
    func test_weekend_notTrading() {
        let d = makeDate(weekday: 1, hour: 10, minute: 0)  // 周日 10:00
        XCTAssertFalse(RefreshScheduler.isTradingHour(at: d))
        let d2 = makeDate(weekday: 7, hour: 10, minute: 0) // 周六 10:00
        XCTAssertFalse(RefreshScheduler.isTradingHour(at: d2))
    }

    // 美股晚间开盘
    func test_usStock_evening_notTrading() {
        let d = makeDate(weekday: 2, hour: 22, minute: 0)  // 周一 22:00（美股盘中）
        XCTAssertFalse(RefreshScheduler.isTradingHour(at: d))
    }

    // 美股凌晨跨日
    func test_usStock_earlyMorning_notTrading() {
        let d = makeDate(weekday: 3, hour: 3, minute: 0)   // 周二 03:00（美股尾盘）
        XCTAssertFalse(RefreshScheduler.isTradingHour(at: d))
    }

    // A股收市后，即使美股盘前也不自动刷新
    func test_afterClose_notTrading() {
        let d = makeDate(weekday: 2, hour: 16, minute: 30) // 周一 16:30
        XCTAssertFalse(RefreshScheduler.isTradingHour(at: d))
    }

    func test_aStock_sessionBoundaries() {
        for (hour, minute, expected) in [(9, 29, false), (9, 30, true), (11, 29, true),
                                         (11, 30, false), (12, 59, false), (13, 0, true),
                                         (14, 59, true), (15, 0, false)] {
            XCTAssertEqual(
                RefreshScheduler.isTradingHour(at: makeDate(weekday: 2, hour: hour, minute: minute)),
                expected,
                "\(hour):\(minute)",
            )
        }
    }

}
