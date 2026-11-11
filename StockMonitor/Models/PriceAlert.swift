// Created by april on 2026/11/11.
import Foundation

struct PriceAlert: Codable, Identifiable, Equatable {
    enum Metric: String, Codable, CaseIterable {
        case price = "价格"
        case percent = "涨跌幅"
    }

    enum Comparison: String, Codable, CaseIterable {
        case atLeast = "≥"
        case atMost = "≤"
    }

    var id = UUID()
    var stockId: String
    var stockName: String
    var metric: Metric
    var comparison: Comparison
    var target: Double
    var isEnabled = true
    var triggeredAt: Date?

    var summary: String {
        "\(metric.rawValue) \(comparison.rawValue) \(target.formatted(.number.precision(.fractionLength(0...4))))\(metric == .percent ? "%" : "")"
    }

    func matches(_ quote: Quote) -> Bool {
        // 行情是外部输入，无效或占位价格不能触发提醒。
        guard isEnabled, quote.price.isFinite, quote.price > 0 else { return false }
        let value = metric == .price ? quote.price : quote.changePercent
        guard value.isFinite else { return false }
        return comparison == .atLeast ? value >= target : value <= target
    }
}
