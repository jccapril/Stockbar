// Created by april on 2026/11/18.
import SwiftUI

struct MarketWindowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @AppStorage("marketWindowStockID") private var selectedID = ""
    @State private var query = ""
    @State private var detailsOpen = false
    @State private var detail = "持仓"
    @State private var chartRefresh = 0

    private var selection: Stock {
        let indices = appState.config.showOverseasIndices ? AppState.marketIndices : IndexMarket.china.stocks
        return (appState.stocks + indices).first { $0.id == selectedID }
            ?? appState.groupedStocks().lazy.flatMap(\.1).first
            ?? IndexMarket.china.stocks[0]
    }

    var body: some View {
        let stock = selection
        let isIndex = AppState.marketIndices.contains { $0.id == stock.id }
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if appState.config.showOverseasIndices {
                    Picker("市场", selection: $appState.indexMarket) {
                        ForEach(IndexMarket.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                ForEach(appState.displayedIndexMarket.stocks) { index in
                    let quote = appState.quotes[index.id]
                    Button {
                        selectedID = index.id
                    } label: {
                        HStack(spacing: 6) {
                            Text(index.name).bold()
                            Text(quote?
                                .formattedPrice ??
                                (appState.failedIndexMarkets.contains(appState.displayedIndexMarket) ? "加载失败" : "—"))
                            Text(quote?.formattedPercent ?? "—")
                                .foregroundStyle(quote.map { appState.quoteColor(for: $0) } ?? .secondary)
                        }
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            .monospacedDigit().padding(12)
            Divider()
            HSplitView {
                sidebar.frame(minWidth: 200, idealWidth: 280, maxWidth: 400)
                VStack(alignment: .leading, spacing: 8) {
                    StockChartView(stock: stock, onClose: {}, isExpanded: true, marketWindow: true)
                        .id("\(stock.id)-\(chartRefresh)")
                    if !isIndex {
                        Divider()
                        DisclosureGroup("个股明细", isExpanded: $detailsOpen) {
                            Picker("明细", selection: $detail) {
                                ForEach(["持仓", "做T记录", "每日收益"], id: \.self) { Text($0) }
                            }.pickerStyle(.segmented).labelsHidden()
                            Group {
                                switch detail {
                                case "做T记录":
                                    TFillHistoryView(stock: stock, store: appState.aiReports, embedded: true)
                                case "每日收益":
                                    DailyTProfitView(stock: stock, store: appState.aiReports, embedded: true)
                                default:
                                    holding(stock)
                                }
                            }.id(stock.id).frame(height: 135)
                        }
                    }
                }
                .padding(12).frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 740, minHeight: detailsOpen && !isIndex ? 700 : 500)
        .toolbar {
            Button {
                appState.forceRefresh()
                chartRefresh += 1
            } label: { Label("刷新", systemImage: "arrow.clockwise") }
            .keyboardShortcut("r").disabled(appState.isLoading)
            Button { openWindow(id: "settings") } label: { Label("设置", systemImage: "gearshape") }
        }
        .background(ChartWindowFrameSaver(name: "Stockbar.MarketWindow"))
        .task(id: appState.displayedIndexMarket) { await appState.refreshSelectedIndices() }
        .onChange(of: appState.displayedIndexMarket) { market in
            if isIndex { selectedID = market.stocks[0].id }
        }
        .onAppear { selectedID = stock.id }
        .onChange(of: stock.id) { selectedID = $0 }
    }

    private var sidebar: some View {
        let groups = appState
            .groupedStocks(searchQuery: appState.config.showListSearch ? query
            .trimmingCharacters(in: .whitespacesAndNewlines) : "")
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("自选股").font(.headline)
                Spacer()
                Button { openWindow(id: "add-stock") } label: { Label("新增股票", systemImage: "plus") }
            }.padding(.horizontal, 10)
            if appState.config.showListSearch {
                TextField("名称或代码", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal, 10)
            }
            List(selection: Binding<String?>(get: { selectedID }, set: { if let id = $0 { selectedID = id } })) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group.1) { stock in
                            let quote = appState.quotes[stock.id]
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(stock.name).lineLimit(1)
                                    Text(stock.id).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(quote?.formattedPrice ?? "—")
                                    Text(quote?.formattedPercent ?? "—").font(.caption)
                                        .foregroundStyle(quote.map { appState.quoteColor(for: $0) } ?? .secondary)
                                }.monospacedDigit()
                            }.tag(stock.id)
                        }
                    } header: {
                        Text(group.2 ?? group.0.rawValue)
                            .contextMenu {
                                if let id = group.3 { GroupOrderButtons(groupID: id) }
                            }
                    }
                }
            }
            .overlay {
                if groups
                    .allSatisfy(\.1.isEmpty) { Text(query.isEmpty ? "暂无自选股" : "没有匹配的股票").foregroundStyle(.secondary) }
            }
        }.padding(.top, 12)
    }

    @ViewBuilder
    private func holding(_ stock: Stock) -> some View {
        if let shares = stock.holdingShares {
            VStack(alignment: .leading, spacing: 8) {
                Text("持仓数量  \(shares.formatted())")
                if let cost = stock.costPrice { Text("成本价  \(cost.formatted())") }
                if let quote = appState.quotes[stock.id], let pnl = stock.pnl(quote: quote) {
                    Text("持仓盈亏  \(pnl.formatted(.number.precision(.fractionLength(2))))")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else { Text("暂无持仓").foregroundStyle(.secondary) }
    }
}
