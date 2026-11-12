// Created by april on 2026/11/11.
import SwiftUI

struct AIAnalysisView: View {
    let stock: Stock
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var horizon = "短线（未来 1–5 个交易日）"
    @State private var analysis: AIAnalysisService.Analysis?
    @State private var requestTask: Task<Void, Never>?
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(stock.name) · AI 分析").font(.title2.bold())
                    Text(stock.id).foregroundColor(.secondary)
                }
                Spacer()
                Button("AI 设置") { openWindow(id: "ai-settings") }
            }
            Picker("分析周期", selection: $horizon) {
                Text("短线").tag("短线（未来 1–5 个交易日）")
                Text("波段").tag("波段（未来 20–60 个交易日）")
            }
            .pickerStyle(.segmented)
            .disabled(requestTask != nil)
            .onChange(of: horizon) { _ in analysis = nil; errorMessage = "" }

            Text("使用最近最多 120 根日 K 和带时间的公开报价。分析不含新闻、财报或成交量，也不了解你的持仓与成本。")
                .font(.caption).foregroundColor(.secondary)
            if !appState.config.aiAPIAddress.isEmpty {
                Text("发送至：\(appState.config.aiAPIAddress)\n模型：\(appState.config.aiModel)")
                    .font(.caption).foregroundColor(.secondary).textSelection(.enabled)
            }
            HStack {
                if requestTask != nil {
                    ProgressView().controlSize(.small)
                    Text("正在获取行情并分析…").font(.callout)
                    Spacer()
                    Button("取消") { requestTask?.cancel() }
                } else {
                    Button(analysis == nil ? "开始分析" : "重新分析") { startAnalysis() }
                        .buttonStyle(.borderedProminent)
                    Text("仅供技术面参考，不代表确定的买卖时机。")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !errorMessage.isEmpty {
                        Text(errorMessage).foregroundColor(.red)
                    }
                    if let analysis {
                        Text("\(analysis.horizon) · 日 K 截至 \(analysis.lastTradingDay)")
                            .font(.caption).foregroundColor(.secondary)
                        Text(
                            "生成于 \(analysis.generatedAt.formatted(date: .abbreviated, time: .shortened)) · \(analysis.model)",
                        )
                            .font(.caption).foregroundColor(.secondary)
                        Text(analysis.text).lineSpacing(6).textSelection(.enabled)
                    } else if requestTask == nil, errorMessage.isEmpty {
                        Text("选择周期后点击“开始分析”，查看技术面信号、判断依据和触发条件。")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(minWidth: 540, minHeight: 500)
        .onDisappear { requestTask?.cancel() }
    }

    private func startAnalysis() {
        errorMessage = ""
        analysis = nil
        let address = appState.config.aiAPIAddress
        let model = appState.config.aiModel
        let quote = appState.quotes[stock.id]
        let selectedHorizon = horizon
        requestTask = Task { @MainActor in
            defer { requestTask = nil }
            do {
                let result = try await AIAnalysisService.analyze(
                    stock: stock,
                    quote: quote,
                    address: address,
                    model: model,
                    horizon: selectedHorizon,
                )
                try Task.checkCancellation()
                analysis = result
            } catch {
                // 主动取消或关闭窗口时不显示网络失败。
                if !Task.isCancelled {
                    errorMessage = error is DecodingError ? "AI 返回的数据格式不兼容，请检查模型和接口。" : error.localizedDescription
                }
            }
        }
    }
}
