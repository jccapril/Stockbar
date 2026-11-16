// Created by april on 2026/11/12.
import Combine
import Foundation
import UserNotifications

struct SavedAIReport: Identifiable, Codable {
    let id: UUID
    let stockID: String
    let stockName: String
    let analysis: AIAnalysisService.Analysis
}

struct TFill: Identifiable, Codable {
    enum Side: String, Codable, CaseIterable {
        case buy = "买入"
        case sell = "卖出"
    }

    let id: UUID
    let time: Date
    let side: Side
    let quantity: Int
    let price: Double
    var assumed: Bool?
}

struct DailyTProfit: Identifiable {
    let id: Date
    let profit: Decimal
    let matched: Int
    let netBought: Int

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    static func history(for stockID: String, reports: [SavedAIReport]) -> [DailyTProfit] {
        let fills = reports.filter { $0.stockID == stockID && $0.analysis.assumedFill != nil }
            .sorted { $0.analysis.generatedAt < $1.analysis.generatedAt }
            .compactMap(\.analysis.assumedFill)
        let calendar = Self.calendar
        let days = Dictionary(grouping: fills) { calendar.startOfDay(for: $0.time) }
        return days.map { date, dayFills in
            let ordered = dayFills.sorted { $0.time < $1.time }
            let buys = ordered.filter { $0.side == .buy }
            let sells = ordered.filter { $0.side == .sell }
            let bought = buys.reduce(0) { $0 + $1.quantity }
            let sold = sells.reduce(0) { $0 + $1.quantity }
            let matched = min(bought, sold)

            // 各取最早成交的等量两侧，无论先买还是先卖，剩余单边数量均未闭合。
            func matchedValue(_ side: [TFill]) -> Decimal {
                var remaining = matched
                var amount = Decimal.zero
                for fill in side {
                    if remaining == 0 { break }
                    let quantity = min(remaining, fill.quantity)
                    amount += Decimal(quantity) * Decimal(fill.price)
                    remaining -= quantity
                }
                return amount
            }
            return DailyTProfit(
                id: date,
                profit: matchedValue(sells) - matchedValue(buys),
                matched: matched,
                netBought: bought - sold,
            )
        }.sorted { $0.id > $1.id }
    }
}

@MainActor
final class AIReportStore: ObservableObject {
    @Published private(set) var reports: [SavedAIReport] = []
    @Published private(set) var errorMessage = ""
    private let directory: URL

    init(directory: URL) {
        self.directory = directory.appendingPathComponent("ai-reports", isDirectory: true)
        reload()
    }

    func reload() {
        errorMessage = ""
        // 首次使用尚未生成报告目录，显示空历史列表。
        guard FileManager.default.fileExists(atPath: directory.path) else { reports = []; return }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            var loaded: [SavedAIReport] = []
            for file in files where file.pathExtension == "json" {
                do {
                    try loaded.append(JSONDecoder().decode(SavedAIReport.self, from: Data(contentsOf: file)))
                } catch {
                    // 单份损坏报告不影响其它记录，保留原文件并明确提示。
                    errorMessage = "部分历史报告读取失败：\(error.localizedDescription)"
                }
            }
            reports = loaded.sorted { $0.analysis.generatedAt > $1.analysis.generatedAt }
        } catch {
            errorMessage = "读取历史报告失败：\(error.localizedDescription)"
        }
    }

    func save(_ analysis: AIAnalysisService.Analysis, for stock: Stock) throws {
        let report = SavedAIReport(id: UUID(), stockID: stock.id, stockName: stock.name, analysis: analysis)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(report)
        try data.write(to: directory.appendingPathComponent("\(report.id.uuidString).json"), options: .atomic)
        reports.append(report)
        reports.sort { $0.analysis.generatedAt > $1.analysis.generatedAt }
        if let decision = analysis.tDecision, decision.action == .buy || decision.action == .sell {
            Task { await notify(report, decision: decision) }
        }
    }

    private func notify(_ report: SavedAIReport, decision: AIAnalysisService.TDecision) async {
        let center = UNUserNotificationCenter.current()
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                errorMessage = "买卖通知未获允许，请在系统设置 → 通知中开启。"
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "\(report.stockName) · \(report.analysis.horizonTitle)"
            var body = decision.action.title
            if let quantity = decision.quantity {
                body += " \(quantity)\(decision.quantityUnit ?? "股")（模拟）"
            }
            if let price = report.analysis.intradayReferencePrice {
                body += " · 参考价 " + price.formatted(.number.precision(.fractionLength(2...3)))
            }
            content.body = body
            content.sound = .default
            try await center.add(UNNotificationRequest(
                identifier: report.id.uuidString,
                content: content,
                trigger: nil,
            ))
        } catch {
            errorMessage = "发送买卖通知失败：\(error.localizedDescription)"
        }
    }
}

extension AIReportStore {
    private func fillsDirectory(for stock: Stock) -> URL {
        directory.appendingPathComponent("fills").appendingPathComponent(stock.id)
    }

    func fills(for stock: Stock) throws -> [TFill] {
        let folder = fillsDirectory(for: stock)
        let assumed = reports.filter { $0.stockID == stock.id }.compactMap(\.analysis.assumedFill)
        guard FileManager.default.fileExists(atPath: folder.path) else { return assumed.sorted { $0.time < $1.time } }
        let manual = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(TFill.self, from: Data(contentsOf: $0)) }
        return (manual + assumed).sorted { $0.time < $1.time }
    }

    func saveFill(_ fill: TFill, for stock: Stock) throws {
        let folder = fillsDirectory(for: stock)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(fill).write(
            to: folder.appendingPathComponent(fill.id.uuidString + ".json"),
            options: .atomic,
        )
    }

    func removeFill(_ fill: TFill, for stock: Stock) throws {
        try FileManager.default
            .removeItem(at: fillsDirectory(for: stock).appendingPathComponent(fill.id.uuidString + ".json"))
    }
}
