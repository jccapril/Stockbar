// Created by april on 2026/11/13.
import Foundation

extension AIAnalysisService {
    /// 模型的结构化候选结论，与当时行情一起保存；不代表真实成交。
    struct TDecision: Codable {
        enum Action: String, Codable {
            case buy = "buy_candidate"
            case sell = "sell_candidate"
            case watch
            case insufficient

            var title: String {
                switch self {
                case .buy: "买入"
                case .sell: "卖出"
                case .watch: "观望"
                case .insufficient: "数据不足"
                }
            }

            var marker: String? {
                switch self {
                case .buy: "B"
                case .sell: "S"
                case .watch, .insufficient: nil
                }
            }
        }

        struct OptionProbability: Codable {
            let value: String
            let probability: Double
        }

        var action: Action
        var probabilities: [OptionProbability]?

        var quantity: Int?
        var quantityUnit: String?

        var displayText: String {
            let title = quantity.map { "\(action.title) · \($0)\(quantityUnit ?? "股")" } ?? action.title
            guard let probabilities else { return title }
            let options = [("buy", "买入"), ("sell", "卖出"), ("watch", "观望")]
            let scores = options.map { key, label in
                let probability = probabilities.first { $0.value == key }?.probability
                let percent = probability.map { String(format: "%.1f%%", $0 * 100) } ?? "—"
                return label + " " + percent
            }
            return title + "\n模型概率  " + scores.joined(separator: " · ")
        }

        // 旧报告保存过这些条件，可用于回顾当日历史信号。
        var entryCondition: String?
        var exitCondition: String?
        var invalidation: String?
    }
}
