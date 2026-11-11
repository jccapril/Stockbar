// Created by april on 2026/11/11.
import SwiftUI

struct PriceAlertView: View {
    let stock: Stock
    @EnvironmentObject var store: PriceAlertStore
    @EnvironmentObject var appState: AppState
    @State private var metric: PriceAlert.Metric = .price
    @State private var comparison: PriceAlert.Comparison = .atLeast
    @State private var targetText = ""
    @State private var editingID: UUID?
    @State private var isSaving = false

    private var target: Double? {
        guard let value = Double(targetText.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite, metric == .percent || value > 0 else { return nil }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(stock.name) · 价格提醒").font(.headline)
            Text(stock.id).font(.caption).foregroundStyle(.secondary)
            HStack {
                Picker("指标", selection: $metric) {
                    ForEach(PriceAlert.Metric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("条件", selection: $comparison) {
                    ForEach(PriceAlert.Comparison.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                TextField(metric == .percent ? "例如 -3 或 5" : "目标价格", text: $targetText)
                    .textFieldStyle(.roundedBorder)
                if metric == .percent { Text("%") }
            }
            Text("涨跌幅按当日昨收计算，价格使用股票原币种。达到条件（含等于）即提醒一次；添加时已满足条件，也会在下次刷新提醒。")
                .font(.caption).foregroundStyle(.secondary)
            if stock.market == .usStock {
                Text("美股按常规交易时段价格判断，不含盘前、盘后及夜盘价格。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                if editingID != nil {
                    Button("取消编辑") { editingID = nil; targetText = "" }
                }
                Button(editingID == nil ? "添加并启用" : "保存并启用") {
                    Task { await saveRule() }
                }
                .disabled(target == nil || isSaving)
                .keyboardShortcut(.defaultAction)
            }
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
                Button("允许通知") { Task { await store.requestPermission() } }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(store.rules.filter { $0.stockId == stock.id }) { rule in
                        ruleRow(rule)
                    }
                    if !store.rules.contains(where: { $0.stockId == stock.id }) {
                        Text("尚未设置提醒").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("仅在应用运行、联网并刷新行情时检查。触发后自动停用，可手动重新启用。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 380)
    }

    private func ruleRow(_ rule: PriceAlert) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.summary)
                if let date = rule.triggeredAt {
                    Text("已触发 · \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(rule.isEnabled ? "监测中" : "已停用")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(rule.isEnabled ? "停用" : "启用") {
                Task {
                    var updated = rule
                    if !rule.isEnabled {
                        guard await store.requestPermission() else { return }
                        updated.triggeredAt = nil
                    }
                    // 权限弹窗期间规则可能已被删除，不重新创建已删除规则。
                    guard store.rules.contains(rule) else { return }
                    updated.isEnabled.toggle()
                    if store.save(updated), updated.isEnabled { appState.forceRefresh() }
                }
            }
            Button("编辑") {
                editingID = rule.id
                metric = rule.metric
                comparison = rule.comparison
                targetText = String(rule.target)
            }
            Button("删除", role: .destructive) { store.remove(rule.id) }
        }
        .disabled(isSaving)
    }

    private func saveRule() async {
        // 表单是外部输入，只接受有限数值，价格必须大于零。
        guard let target else { return }
        var rule = PriceAlert(
            stockId: stock.id,
            stockName: stock.name,
            metric: metric,
            comparison: comparison,
            target: target,
        )
        if let editingID { rule.id = editingID }
        isSaving = true
        defer { isSaving = false }
        guard await store.requestPermission() else { return }
        if store.save(rule) {
            editingID = nil
            targetText = ""
            appState.forceRefresh()
        }
    }
}
