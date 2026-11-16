// Created by april on 2026/11/13.
import SwiftUI

/// 同一分钟的多份候选报告合并为一个标记，点击仍可查看每份原始报告。
struct TAnalysisChartMarker: Identifiable {
    let pointID: Int
    let reports: [SavedAIReport]

    var id: UUID { report.id }
    var report: SavedAIReport { reports[0] }
    var price: Double { report.analysis.intradayReferencePrice! }
    var label: String {
        let decision = report.analysis.tDecision!
        let marker = decision.action.marker!
        guard let quantity = decision.quantity else { return marker }
        return "\(marker) \(quantity)\(decision.quantityUnit ?? "股")"
    }

    var isBuy: Bool { report.analysis.tDecision?.action == .buy }

    static func make(reports: [SavedAIReport], points: [MinutePoint]) -> [TAnalysisChartMarker] {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "Asia/Shanghai")
        day.dateFormat = "yyyyMMdd"
        let time = DateFormatter()
        time.locale = day.locale
        time.timeZone = day.timeZone
        time.dateFormat = "HHmm"
        var grouped: [Int: [SavedAIReport]] = [:]
        for report in reports {
            // 老报告没有结构化结论，不通过正文关键词推测 B/S。
            guard report.analysis.tDecision?.action.marker != nil,
                  let asOf = report.analysis.intradayAsOf,
                  let price = report.analysis.intradayReferencePrice, price.isFinite, price > 0,
                  let point = points.first(where: {
                      $0.day == day.string(from: asOf) && $0.time.replacingOccurrences(of: ":", with: "") == time
                          .string(from: asOf)
                  }) else { continue }
            grouped[point.id, default: []].append(report)
        }
        return grouped.flatMap { key, values in
            Dictionary(grouping: values, by: { $0.analysis.tDecision!.action.rawValue }).values.map { matching in
                TAnalysisChartMarker(pointID: key, reports: matching.sorted { lhs, rhs in
                    if (lhs.analysis.tDecision?.quantity != nil) != (rhs.analysis.tDecision?.quantity != nil) {
                        return lhs.analysis.tDecision?.quantity != nil
                    }
                    return lhs.analysis.generatedAt > rhs.analysis.generatedAt
                })
            }
        }.sorted { $0.pointID < $1.pointID }
    }
}

struct TAnalysisMarkerDetail: View {
    let marker: TAnalysisChartMarker

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("当时的 AI 分析").font(.headline)
                ForEach(marker.reports) { report in
                    Text("\(report.stockName) · \(report.stockID)").font(.subheadline.bold())
                    AIReportContentView(analysis: report.analysis)
                    Divider()
                }
            }
            .padding(16)
        }
        .frame(width: 440, height: 420)
    }
}
