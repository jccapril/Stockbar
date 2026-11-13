// Created by april on 2026/11/13.
import Foundation

/// 仅用本机连续收到的行情计算滚动涨跌；重启或长时间断更后重新累计。
struct RapidMoveTracker {
    private struct Sample {
        let date: Date
        let value: Double
        let sourceTime: String
    }

    private var samples: [Sample] = []
    private var startedAt: Date?

    mutating func observe(_ quote: Quote, at now: Date, rule: PriceAlert) -> Double? {
        // 外部行情中的占位值和无效价格不能触发提醒，也不能作为比较基准。
        guard quote.price.isFinite, quote.price > 0, !quote.updateTime.isEmpty else {
            samples.removeAll()
            startedAt = nil
            return nil
        }
        // 超过 90 秒没有新行情时重新累计，避免跨午休、收盘或网络中断比较。
        if let last = samples.last, now.timeIntervalSince(last.date) > 90 {
            samples.removeAll()
            startedAt = nil
        }
        // 同一份行情不重复计时，防止缓存报价被当作持续实时行情。
        if samples.last?.sourceTime == quote.updateTime { return nil }
        if startedAt == nil { startedAt = now }
        samples.append(Sample(date: now, value: quote.price, sourceTime: quote.updateTime))
        let cutoff = now.addingTimeInterval(-Double(rule.windowMinutes * 60))
        // 只比较窗口内的样本，不用窗口外更早的价格放大涨跌幅。
        while samples.count > 1, samples[0].date < cutoff {
            samples.removeFirst()
        }
        guard let startedAt, startedAt <= cutoff, samples.count > 1,
              let baseline = samples.first else { return nil }
        let change = (quote.price / baseline.value - 1) * 100
        // 冷却期间继续采集行情，恢复后仍然比较最近的时间窗口。
        if let lastTrigger = rule.triggeredAt,
           now.timeIntervalSince(lastTrigger) < Double(rule.cooldownMinutes * 60) { return nil }
        let matches = rule.metric == .rapidRise
            ? quote.price >= baseline.value * (1 + rule.target / 100)
            : quote.price <= baseline.value * (1 - rule.target / 100)
        return matches ? change : nil
    }
}
