// Created by april on 2026/11/11.
import Foundation

enum ChartPreferences {
    static var period: ChartPeriod {
        get {
            UserDefaults.standard.string(forKey: "chart.lastPeriod").flatMap(ChartPeriod.init(rawValue:)) ?? .intraday
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "chart.lastPeriod") }
    }

    static func visibleCount(for period: CandlePeriod) -> Int {
        let saved = UserDefaults.standard.integer(forKey: "chart.visibleCount.\(period.rawValue)")
        // 偏好来自持久化输入，缺失或超出支持范围时使用默认缩放。
        return (10...240).contains(saved) ? saved : 60
    }

    static func rememberVisibleCount(_ count: Int, for period: CandlePeriod) {
        UserDefaults.standard.set(min(240, max(10, count)), forKey: "chart.visibleCount.\(period.rawValue)")
    }
}
