// Created by april on 2026/11/12.
import Combine
import Foundation

struct SavedAIReport: Identifiable, Codable {
    let id: UUID
    let stockID: String
    let stockName: String
    let analysis: AIAnalysisService.Analysis
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
    }
}
