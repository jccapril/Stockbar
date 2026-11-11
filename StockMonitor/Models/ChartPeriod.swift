// Created by april on 2026/11/11.
import Foundation

enum ChartPeriod: String, CaseIterable {
    case intraday = "分时"
    case fiveDays = "五日"
    case daily = "日 K"
    case weekly = "周 K"
    case monthly = "月 K"

    var candlePeriod: CandlePeriod? {
        switch self {
        case .intraday, .fiveDays: nil
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        }
    }
}

enum CandlePeriod: String {
    case daily = "day"
    case weekly = "week"
    case monthly = "month"

    var yahooInterval: String {
        switch self {
        case .daily: "1d"
        case .weekly: "1wk"
        case .monthly: "1mo"
        }
    }
}

struct CandlePoint: Identifiable {
    var id: String { date }
    let date: String // 交易日、周一或月份首日，yyyy-MM-dd
    let open: Double
    let close: Double
    let high: Double
    let low: Double
    var previousClose: Double?

    var changePercent: Double? {
        previousClose.map { (close / $0 - 1) * 100 }
    }
}
