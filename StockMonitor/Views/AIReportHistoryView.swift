// Created by april on 2026/11/12.
import SwiftUI

struct AIReportHistoryView: View {
    @EnvironmentObject var store: AIReportStore
    @State private var selectedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("历史报告").font(.title2.bold())
                Text("\(store.reports.count) 份 · 最新在前").foregroundStyle(.secondary)
                Spacer()
                Button("刷新") { store.reload() }
            }
            .padding(20)
            if !store.errorMessage.isEmpty {
                Text(store.errorMessage).foregroundStyle(.red).padding(.horizontal, 20)
            }
            Divider()
            if store.reports.isEmpty {
                Text("暂无历史报告。完成一次 AI 分析后，报告会自动保存在本机。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
            } else {
                HSplitView {
                    List(store.reports, selection: $selectedID) { report in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(report.stockName) · \(report.stockID)").font(.headline)
                            Text(report.analysis.generatedAt.formatted(date: .numeric, time: .standard))
                            Text(report.analysis.horizon)
                            Text(report.analysis.model)
                        }
                        .font(.caption)
                        .padding(.vertical, 6)
                        .tag(report.id)
                    }
                    .frame(minWidth: 230, idealWidth: 260, maxWidth: 340)
                    ScrollView {
                        if let report = store.reports.first(where: { $0.id == selectedID }) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("\(report.stockName) · \(report.stockID)").font(.title2.bold())
                                AIReportContentView(analysis: report.analysis)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(24)
                        } else {
                            Text("选择左侧报告查看全文").foregroundStyle(.secondary).padding(24)
                        }
                    }
                    .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            store.reload()
            selectedID = store.reports.first?.id
        }
        .onChange(of: store.reports.count) { _ in
            // 第一份报告保存后自动选中；阅读过程中不跳到其它报告。
            if selectedID == nil { selectedID = store.reports.first?.id }
        }
    }
}

struct AIReportContentView: View {
    let analysis: AIAnalysisService.Analysis

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(analysis.horizon) · 日 K 截至 \(analysis.lastTradingDay)")
                .font(.caption).foregroundStyle(.secondary)
            Text("生成于 \(analysis.generatedAt.formatted(date: .numeric, time: .standard)) · \(analysis.model)")
                .font(.caption).foregroundStyle(.secondary)
            Text(analysis.text).lineSpacing(6).textSelection(.enabled)
        }
    }
}
