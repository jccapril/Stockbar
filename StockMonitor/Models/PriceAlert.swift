// Created by april on 2026/11/11.
import Foundation

struct PriceAlert: Codable, Identifiable, Equatable {
    enum Metric: String, Codable, CaseIterable {
        case price = "价格"
        case percent = "涨跌幅"
        case rapidRise = "快速上涨"
        case rapidFall = "快速下跌"

        var isRapid: Bool { self == .rapidRise || self == .rapidFall }
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
    var windowMinutes = 5
    var cooldownMinutes = 10

    static let validWindows = [1, 3, 5, 10]
    static let validCooldowns = [1, 5, 10, 30, 60]

    var summary: String {
        if metric.isRapid {
            return "\(windowMinutes) 分钟\(metric == .rapidRise ? "上涨" : "下跌") ≥ \(target.formatted())% · 冷却 \(cooldownMinutes) 分钟"
        }
        return "\(metric.rawValue) \(comparison.rawValue) \(target.formatted(.number.precision(.fractionLength(0...4))))\(metric == .percent ? "%" : "")"
    }

    func matches(_ quote: Quote) -> Bool {
        // 行情是外部输入，无效或占位价格不能触发提醒。
        guard isEnabled, !metric.isRapid, quote.price.isFinite, quote.price > 0 else { return false }
        let value = metric == .price ? quote.price : quote.changePercent
        guard value.isFinite else { return false }
        return comparison == .atLeast ? value >= target : value <= target
    }
}

extension PriceAlert {
    enum CodingKeys: String, CodingKey {
        case id, stockId, stockName, metric, comparison, target, isEnabled, triggeredAt
        case windowMinutes, cooldownMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        stockId = try c.decode(String.self, forKey: .stockId)
        stockName = try c.decode(String.self, forKey: .stockName)
        metric = try c.decode(Metric.self, forKey: .metric)
        comparison = try c.decode(Comparison.self, forKey: .comparison)
        target = try c.decode(Double.self, forKey: .target)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        triggeredAt = try c.decodeIfPresent(Date.self, forKey: .triggeredAt)
        windowMinutes = try c.decodeIfPresent(Int.self, forKey: .windowMinutes) ?? 5
        cooldownMinutes = try c.decodeIfPresent(Int.self, forKey: .cooldownMinutes) ?? 10
    }
}
