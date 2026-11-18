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
    @State private var reportSaved = false

    @State private var balanceDate = Date()
    @State private var openingShares = ""
    @State private var currentShares = ""
    @State private var sellableShares = ""
    private var continuousT: Bool { appState.positionSchedules[stock.id] != nil }
    @State private var showingDailyProfit = false
    @State private var showingFills = false
    @State private var tradingCash = ""

    private var position: AIAnalysisService.TPosition? {
        guard let opening = Int(openingShares), let held = Int(currentShares),
              let sellable = Int(sellableShares), sellable >= 0, sellable <= min(opening, held),
              let cash = Double(tradingCash), cash.isFinite, cash >= 0 else { return nil }
        return .init(held: held, sellable: sellable, cash: cash, opening: opening)
    }

    private var isIntradayMode: Bool {
        horizon == AIAnalysisService.positionTHorizon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(stock.name) · AI 分析").font(.title2.bold())
                    Text(stock.id).foregroundColor(.secondary)
                }
                Spacer()
                Button("历史报告") { openWindow.replacingSource(id: "ai-history") }
                Button("AI 设置") { openWindow.replacingSource(id: "ai-settings") }
            }
            Picker("分析周期", selection: $horizon) {
                if stock.market == .aStock, !IndexMarket.china.stocks.contains(where: { $0.id == stock.id }) {
                    Text("做T").tag(AIAnalysisService.positionTHorizon)
                }
                Text("短线").tag("短线（未来 1–5 个交易日）")
                Text("波段").tag("波段（未来 20–60 个交易日）")
            }
            .pickerStyle(.segmented)
            .disabled(requestTask != nil)
            .onChange(of: horizon) { _ in
                if requestTask == nil { analysis = nil; errorMessage = "" }
            }

            if horizon == AIAnalysisService.positionTHorizon {
                HStack {
                    Toggle("盘中自动分析", isOn: Binding(get: { continuousT }, set: { enabled in
                        settleNewDay()
                        let schedule = enabled ? position.map { AppState.PositionSchedule(
                            minutes: 5,
                            balance: $0,
                            createdAt: Date(),
                        ) } : nil
                        appState.setPositionSchedule(schedule, for: stock.id)
                    }))
                    .toggleStyle(.checkbox)
                    .disabled(!continuousT && (position == nil || appState.runningTStocks.contains(stock.id)))
                    if let schedule = appState.positionSchedules[stock.id] {
                        Stepper("每 \(schedule.minutes) 分钟", value: Binding(
                            get: { schedule.minutes },
                            set: { minutes in
                                var updated = schedule
                                updated.minutes = minutes
                                appState.setPositionSchedule(updated, for: stock.id)
                            },
                        ), in: 1...240)
                        .fixedSize()
                    }
                }
                if let message = appState.automaticTErrors[stock.id] {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
                Grid(alignment: .leading) {
                    GridRow {
                        Text("昨收底仓")
                        TextField("股 / 份", text: $openingShares)
                        Text("当前持仓")
                        TextField("股 / 份", text: $currentShares)
                    }
                    GridRow {
                        Text("当前可卖")
                        TextField("券商可卖数量", text: $sellableShares)
                        Text("可用资金")
                        TextField("扣除预留费用后，元", text: $tradingCash)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .disabled(requestTask != nil || continuousT)
                HStack {
                    Button("每日收益") { showingDailyProfit = true }
                    Button("成交记录…") { showingFills = true }
                        .disabled(requestTask != nil)
                    Text("AI 买卖建议按参考价自动模拟成交，并更新本股余额。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .sheet(isPresented: $showingDailyProfit) {
                    DailyTProfitView(stock: stock, store: appState.aiReports)
                }
                .sheet(isPresented: $showingFills) {
                    TFillHistoryView(stock: stock, store: appState.aiReports)
                }
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
                        .disabled((horizon == AIAnalysisService.positionTHorizon && position == nil) ||
                                  (isIntradayMode && appState.runningTStocks.contains(stock.id)))
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
                        AIReportContentView(analysis: analysis)
                        if reportSaved {
                            Text("已保存至历史报告").font(.caption).foregroundStyle(.secondary)
                        }
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
        .onAppear {
            if let balance = appState.scheduledPosition(for: stock.id) {
                balanceDate = Date()
                display(balance)
            } else if let report = appState.aiReports.reports
                .first(where: { $0.stockID == stock.id && $0.analysis.endingPosition != nil }),
               let balance = report.analysis.endingPosition {
                balanceDate = report.analysis.generatedAt
                display(balance)
                settleNewDay()
            } else if currentShares.isEmpty, let shares = stock.holdingShares, let whole = Int(exactly: shares) {
                currentShares = String(whole)
            }
        }
        .onReceive(appState.aiReports.$reports) { reports in
            guard let schedule = appState.positionSchedules[stock.id],
                  let report = reports.first(where: { $0.stockID == stock.id && $0.analysis.endingPosition != nil }),
                  report.analysis.generatedAt >= schedule.createdAt,
                  let balance = report.analysis.endingPosition else { return }
            balanceDate = report.analysis.generatedAt
            display(balance)
            settleNewDay()
            if horizon == AIAnalysisService.positionTHorizon { analysis = report.analysis; reportSaved = true }
        }
        .onDisappear { requestTask?.cancel() }
    }

    private func display(_ balance: AIAnalysisService.TPosition) {
        openingShares = String(balance.opening)
        currentShares = String(balance.held)
        sellableShares = String(balance.sellable)
        tradingCash = String(balance.cash)
    }

    private func settleNewDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        if !calendar.isDate(balanceDate, inSameDayAs: Date()) {
            openingShares = currentShares
            sellableShares = currentShares
            balanceDate = Date()
        }
    }

    private func startAnalysis() {
        let intraday = isIntradayMode
        if intraday, !appState.beginTRequest(for: stock.id) { return }
        if horizon == AIAnalysisService.positionTHorizon { settleNewDay() }
        errorMessage = ""
        analysis = nil
        reportSaved = false
        let address = appState.config.aiAPIAddress
        let model = appState.config.aiModel
        let quote = appState.quotes[stock.id]
        let selectedHorizon = horizon
        let selectedPosition = selectedHorizon == AIAnalysisService.positionTHorizon ? position : nil
        requestTask = Task { @MainActor in
            defer {
                requestTask = nil
                if intraday { appState.finishTRequest(for: stock.id) }
            }
            do {
                let result = try await AIAnalysisService.analyze(
                    stock: stock,
                    quote: quote,
                    address: address,
                    model: model,
                    horizon: selectedHorizon,
                    reports: selectedPosition != nil ? appState.aiReports.reports : [],
                    position: selectedPosition,
                    fills: selectedPosition == nil ? [] : appState.aiReports.fills(for: stock),
                )
                try Task.checkCancellation()
                analysis = result
                do {
                    try appState.aiReports.save(result, for: stock)
                    if let balance = result.endingPosition { display(balance) }
                    reportSaved = true
                } catch {
                    if selectedPosition != nil { appState.setPositionSchedule(nil, for: stock.id) }
                    errorMessage = "报告已生成，但保存失败：\(error.localizedDescription)"
                }
            } catch {
                // 主动取消或关闭窗口时不显示网络失败。
                if !Task.isCancelled {
                    errorMessage = error is DecodingError ? "AI 返回的数据格式不兼容，请检查模型和接口。" : error.localizedDescription
                }
            }
        }
    }
}

struct TFillHistoryView: View {
    let stock: Stock
    let store: AIReportStore
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @State private var fills: [TFill] = []
    @State private var side = TFill.Side.buy
    @State private var time = Date()
    @State private var quantity = ""
    @State private var price = ""
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !embedded {
                HStack {
                    Text("\(stock.name) · 成交记录").font(.headline)
                    Spacer()
                    Button("完成") { dismiss() }
                }
                DatePicker("成交时间", selection: $time, in: ...Date())
                HStack {
                    Picker("方向", selection: $side) {
                        ForEach(TFill.Side.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().frame(width: 85)
                    TextField("成交数量", text: $quantity)
                    TextField("成交价", text: $price)
                    Button("记录成交") { record() }
                }
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            if !embedded { Text("做T分析会将这些成交明细发送至你配置的 AI 服务。")
                .font(.caption).foregroundStyle(.secondary)
            }
            List(fills.reversed()) { fill in
                HStack {
                    Text(fill.time.formatted(date: .numeric, time: .standard))
                    Spacer()
                    Text(
                        "\(fill.side.rawValue) \(fill.quantity) × \(fill.price.formatted(.number.precision(.fractionLength(0...4))))",
                    )
                    if fill.assumed == true {
                        Text("AI 模拟").foregroundStyle(.secondary)
                    } else if !embedded {
                        Button("删除", role: .destructive) {
                        do {
                            try store.removeFill(fill, for: stock)
                            reload()
                        } catch { self.error = error.localizedDescription }
                        }
                    }
                }
            }
            .overlay { if fills.isEmpty, error.isEmpty { Text("暂无成交记录").foregroundStyle(.secondary) } }
        }
        .padding(20)
        .frame(width: embedded ? nil : 540, height: embedded ? nil : 400)
        .onReceive(store.$reports) { _ in Task { @MainActor in reload() } }
    }

    private func record() {
        guard let count = Int(quantity), count > 0, let value = Double(price), value.isFinite, value > 0 else {
            error = "请输入正整数成交数量和大于零的成交价。"
            return
        }
        do {
            try store.saveFill(TFill(id: UUID(), time: time, side: side, quantity: count, price: value), for: stock)
            quantity = ""
            price = ""
            reload()
        } catch { self.error = error.localizedDescription }
    }

    private func reload() {
        do {
            fills = try store.fills(for: stock)
            error = ""
        } catch { self.error = error.localizedDescription }
    }
}

struct DailyTProfitView: View {
    let stock: Stock
    @ObservedObject var store: AIReportStore
    var embedded = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let days = DailyTProfit.history(for: stock.id, reports: store.reports)
        let unit = store.reports.first { $0.stockID == stock.id && $0.analysis.assumedFill != nil }?.analysis.tDecision?
            .quantityUnit ?? "股"
        VStack(alignment: .leading, spacing: 12) {
            if !embedded {
                HStack {
                    Text("\(stock.name) · 每日做T收益").font(.headline)
                    Spacer()
                    Button("完成") { dismiss() }
                }
            }
            Text("按当日 AI 模拟成交先进先出配对，仅统计已配对价差，未扣手续费及税费。")
                .font(.caption).foregroundStyle(.secondary)
            if days.isEmpty {
                Text("暂无做T模拟成交").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(days) {
                    TableColumn("交易日") { day in
                        Text(day.id.formatted(Date.FormatStyle(
                            date: .numeric,
                            time: .omitted,
                            timeZone: DailyTProfit.calendar.timeZone,
                        )))
                    }
                    TableColumn("已配对收益（元）") { day in
                        Text(day.profit.formatted(.number.precision(.fractionLength(2))))
                            .monospacedDigit()
                    }
                    TableColumn("已配对") { day in Text("\(day.matched)\(unit)") }
                    TableColumn("未配对") { day in
                        Text(day
                            .netBought == 0 ? "—" : "\(day.netBought > 0 ? "买入" : "卖出") \(abs(day.netBought))\(unit)")
                    }
                }
            }
        }
        .padding(20)
        .frame(width: embedded ? nil : 580, height: embedded ? nil : 380)
    }
}
