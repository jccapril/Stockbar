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
                            Text(report.analysis.horizonTitle)
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
            if let asOf = analysis.intradayAsOf {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text(AIAnalysisService.tSnapshotStatus(asOf: asOf, now: context.date))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text(
                    "行情截至 \(asOf.formatted(Date.FormatStyle(date: .numeric, time: .standard, timeZone: TimeZone(identifier: "Asia/Shanghai")!))) · 北京时间",
                )
                    .font(.caption).foregroundStyle(.secondary)
                if let summary = analysis.intradaySummary {
                    let prefix = AIAnalysisService.tAssumption + "\n"
                    let visibleSummary = summary.hasPrefix(prefix) ? String(summary.dropFirst(prefix.count)) : summary
                    Text(visibleSummary).font(.callout).textSelection(.enabled)
                }
            }
            Text(analysis
                .intradayAsOf == nil ? "\(analysis.horizonTitle) · 日 K 截至 \(analysis.lastTradingDay)" : analysis
                .horizonTitle)
                .font(.caption).foregroundStyle(.secondary)
            Text("生成于 \(analysis.generatedAt.formatted(date: .numeric, time: .standard)) · \(analysis.model)")
                .font(.caption).foregroundStyle(.secondary)
            SelectableReportText(text: analysis.text)
        }
    }
}

/// 共用于报告窗口和图表弹窗，支持原生字符选择及复制菜单。
private struct SelectableReportText: NSViewRepresentable {
    let text: String

    func makeNSView(context _: Context) -> NSTextView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = true
        return view
    }

    func updateNSView(_ view: NSTextView, context _: Context) {
        // 状态刷新时保留用户已选中的范围。
        guard view.string != text else { return }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        view.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: NSFont.preferredFont(forTextStyle: .body), .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
        ]))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context _: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, let container = nsView.textContainer,
              let layout = nsView.layoutManager else { return nil }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: ceil(layout.usedRect(for: container).height))
    }
}
