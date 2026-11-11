import SwiftUI

struct DropdownView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false
    @State private var sortByChange = false
    @State private var searchText = ""

    private var searchQuery: String {
        appState.config.showListSearch ? searchText.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    @State private var selectedStock: Stock? = nil
    @State private var dropFrames: [String: CGRect] = [:]
    @State private var dragLocation: CGPoint?
    @State private var draggedStock: Stock?
    @State private var rowFrames: [String: CGRect] = [:]

    private var pinDropFrame: CGRect? { dropFrames["pinned"] }

    private var isPinDropTargeted: Bool {
        dragLocation.map { pinDropFrame?.contains($0) == true } ?? false
    }

    /// 分组数据：(market, stocks, customTitle?)
    private var groupedStocks: [(Market, [Stock], String?)] {
        let rule = appState.config.sortRule
        let usMode = appState.config.usPriceMode
        let doSort = sortByChange

        func sorted(_ stocks: [Stock], market: Market) -> [Stock] {
            guard doSort else { return stocks }
            return stocks.sorted { a, b in
                let va = sortValue(quote: appState.quotes[a.id], market: market, mode: usMode)
                let vb = sortValue(quote: appState.quotes[b.id], market: market, mode: usMode)
                return rule == .changeDesc ? va > vb : va < vb
            }
        }

        var result: [(Market, [Stock], String?)] = []
        let indexIDs = Set(AppState.marketIndices.map(\.id))
        let listStocks = appState.stocks.filter { !indexIDs.contains($0.id) && $0.matchesListSearch(searchQuery) }
        let pinnedStocks = listStocks.filter(\.isPinned)
        let unpinnedStocks = listStocks.filter { !$0.isPinned }

        // 置顶组独立于市场和持仓分组，涨跌幅排序不会把它移到下方。
        if !pinnedStocks.isEmpty {
            result.append((.aStock, pinnedStocks, "置顶"))
        }

        // 持仓股单独分组
        if appState.config.groupHoldings {
            let holdings = unpinnedStocks.filter { $0.holdingShares != nil }
            if !holdings.isEmpty {
                // 持仓组内按第一只股票的市场类型排序（混合市场）
                let sortedHoldings = doSort ? holdings.sorted { a, b in
                    let va = sortValue(quote: appState.quotes[a.id], market: a.market, mode: usMode)
                    let vb = sortValue(quote: appState.quotes[b.id], market: b.market, mode: usMode)
                    return rule == .changeDesc ? va > vb : va < vb
                } : holdings
                result.append((.aStock, sortedHoldings, "持仓"))
            }
            let holdingIds = Set(holdings.map(\.id))
            for market in [Market.aStock, .hkStock, .usStock, .krStock] {
                let s = unpinnedStocks.filter { $0.market == market && !holdingIds.contains($0.id) }
                if !s.isEmpty { result.append((market, sorted(s, market: market), nil)) }
            }
        } else {
            for market in [Market.aStock, .hkStock, .usStock, .krStock] {
                let s = unpinnedStocks.filter { $0.market == market }
                if !s.isEmpty { result.append((market, sorted(s, market: market), nil)) }
            }
        }

        return result
    }

    private var stockListView: some View {
        let groups = groupedStocks
        return ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                // 首次置顶也提供固定落点，拖动过程中不改变列表布局。
                if !groups.contains(where: { $0.2 == "置顶" }) {
                    Label("拖到这里置顶", systemImage: "pin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(isPinDropTargeted ? 0.18 : 0.04))
                        .cornerRadius(6)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(
                                key: StockDropFramesKey.self,
                                value: ["pinned": geometry.frame(in: .named("stockList"))],
                            )
                        })
                }
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    StockGroupView(
                        market: group.0,
                        stocks: group.1,
                        title: group.2,
                        onSelect: { selectedStock = $0 },
                        onDragChange: { stock, location in
                                       draggedStock = stock
                                       dragLocation = location
                                   },
                        onDrop: moveStock,
                    )
                        .id("\(group.0.rawValue)-\(group.2 ?? "")-\(searchQuery)")
                        .background(GeometryReader { geometry in
                            if group.2 == "置顶" {
                                Color.clear.preference(
                                    key: StockDropFramesKey.self,
                                    value: ["pinned": geometry.frame(in: .named("stockList"))],
                                )
                            }
                        })
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(group.2 == "置顶" && isPinDropTargeted ? Color.accentColor : .clear)
                            .allowsHitTesting(false))
                }
                // 全部股票都置顶时，也留出可以拖回普通列表的落点。
                if groups.count == 1, groups.first?.2 == "置顶" {
                    Label("拖到这里取消置顶", systemImage: "pin.slash")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(
                                key: StockDropFramesKey.self,
                                value: ["unpinnedEmpty": geometry.frame(in: .named("stockList"))],
                            )
                        })
                }
            }
            .padding(.horizontal, 6)
        }
        .scrollIndicators(.never)
        .frame(maxHeight: 520)
        .background(GeometryReader { geometry in
            Color.clear.preference(
                key: StockDropFramesKey.self,
                value: ["list": geometry.frame(in: .named("stockList"))],
            )
        })
        .overlay(alignment: .topLeading) {
            if let stock = draggedStock, let location = dragLocation,
               let placement = dropPlacement(for: stock, at: location), let y = placement.lineY {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 6)
                    .offset(y: y)
                    .allowsHitTesting(false)
            }
        }
        .clipped()
        .coordinateSpace(name: "stockList")
        .onPreferenceChange(StockDropFramesKey.self) { dropFrames = $0 }
        .onPreferenceChange(StockRowFramesKey.self) { frames in
            // 拖动中保留起始行位置，用松手位置决定插入点。
            if dragLocation == nil { rowFrames = frames }
        }
    }

    private func dropPlacement(for stock: Stock, at location: CGPoint) -> (pinned: Bool, index: Int, lineY: CGFloat?)? {
        // 松手和提示线共用落点规则，面板外不显示提示、不执行移动。
        guard dropFrames["list"]?.contains(location) == true else { return nil }
        let pinned = pinDropFrame?.contains(location) == true
        let ordered = groupedStocks.flatMap(\.1).filter { $0.id != stock.id }
        let isHoldingGroup = appState.config.groupHoldings && stock.holdingShares != nil
        let candidates = ordered.filter { candidate in
            // 置顶组可跨市场；取消置顶后遵循原有持仓和市场分组规则。
            if pinned { return candidate.isPinned }
            if candidate.isPinned { return false }
            let candidateIsHolding = appState.config.groupHoldings && candidate.holdingShares != nil
            return isHoldingGroup ? candidateIsHolding : !candidateIsHolding && candidate.market == stock.market
        }
        let next = candidates.first { candidate in
            // 收起的分组没有行坐标，展开的行按上半区/下半区决定前后位置。
            guard let frame = rowFrames[candidate.id] else { return false }
            return location.y < frame.midY
        }
        if let next, let index = ordered.firstIndex(where: { $0.id == next.id }) {
            return (pinned, index, rowFrames[next.id].map { $0.minY - 1 })
        }
        if let last = candidates.last, let index = ordered.firstIndex(where: { $0.id == last.id }) {
            return (pinned, index + 1, rowFrames[last.id].map { $0.maxY + 1 })
        }
        // 空分组使用专用落点；只有拖动行时，在其原位置显示提示。
        let frame = pinned ? pinDropFrame : dropFrames["unpinnedEmpty"] ?? rowFrames[stock.id]
        return (pinned, ordered.count, frame?.midY)
    }

    private func moveStock(_ stock: Stock, at location: CGPoint) {
        guard let placement = dropPlacement(for: stock, at: location) else { return }
        var moved = stock
        moved.isPinned = placement.pinned
        var ordered = groupedStocks.flatMap(\.1).filter { $0.id != stock.id }
        ordered.insert(moved, at: placement.index)

        // 只重排本次搜索结果的槽位，保留未匹配的股票和固定指数。
        let visibleIDs = Set(ordered.map(\.id))
        var updated = appState.stocks
        let positions = updated.indices.filter { visibleIDs.contains(updated[$0].id) }
        for (position, item) in zip(positions, ordered) {
            updated[position] = item
        }
        appState.stocks = updated
        sortByChange = false
    }

    private func sortValue(quote: Quote?, market: Market, mode: USPriceMode) -> Double {
        guard let q = quote else { return -Double.infinity }
        if market == .usStock, mode == .sessionPrice, let ext = q.extendedPrice {
            // 用时段价格算涨跌幅：(盘外价 - 正盘价) / 正盘价
            return q.price > 0 ? (ext - q.price) / q.price * 100 : q.changePercent
        }
        return q.changePercent
    }

    private var marketIndexCards: some View {
        VStack(spacing: 4) {
            if appState.config.showOverseasIndices {
                Picker("指数市场", selection: $appState.indexMarket) {
                    ForEach(IndexMarket.allCases, id: \.self) { market in
                        Text(market.rawValue).tag(market)
                    }
                }
                .pickerStyle(.segmented)
            }
            GeometryReader { geometry in
                HStack(spacing: 6) {
                    ForEach(appState.displayedIndexMarket.stocks) { index in
                        let quote = appState.quotes[index.id]
                        let color = quote.map { appState.quoteColor(for: $0) } ?? .secondary
                        Button {
                            selectedStock = index
                        } label: {
                            VStack(spacing: 3) {
                                Text(index.name)
                                    .font(.system(size: 12, weight: .medium))
                                Text(quote?
                                    .formattedPrice ??
                                    (appState.failedIndexMarkets
                                    .contains(appState.displayedIndexMarket) ? "加载失败" : "--"))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(color)
                                Text(quote?.formattedPercent ?? "--")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(color)
                            }
                            .monospacedDigit()
                            .frame(width: (geometry.size.width - 12) / 3)
                            .frame(height: 66)
                            .background(color.opacity(0.08))
                            .cornerRadius(8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("查看\(index.name)分时走势")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: 66)
        }
        .padding(.horizontal, 6)
        .task(id: appState.displayedIndexMarket) { await appState.refreshSelectedIndices() }
        .onChange(of: appState.displayedIndexMarket) { _ in
            if let selectedStock, AppState.marketIndices.contains(where: { $0.id == selectedStock.id }) {
                self.selectedStock = nil
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showSettings {
                SettingsView(showSettings: $showSettings)
            } else {
                ProfitSummaryView()

                marketIndexCards

                if selectedStock == nil, appState.config.showListSearch {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索列表：名称或代码", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("清空搜索")
                        }
                    }
                    .padding(6)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 6)
                }

                if let stock = selectedStock {
                    StockChartView(stock: stock, onClose: { selectedStock = nil })
                        // 切换指数时重建图表状态，并重新请求对应的分时数据。
                        .id(stock.id)
                } else if groupedStocks.isEmpty {
                    Text(searchQuery.isEmpty ? "暂无股票，点击下方“新增”添加" : "没有匹配的股票")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    stockListView
                }

                Divider()
                ToolbarView(showSettings: $showSettings, sortByChange: $sortByChange)
            }
        }
        .padding(6)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(StatusPanelObserver { focused in
            let wasOpen = appState.isStatusPanelOpen
            appState.isStatusPanelOpen = focused
            // 每次打开快照一次，随后保留用户的返回列表、切换股票等操作。
            if focused, !wasOpen, appState.isStatusBarRotating {
                showSettings = false
                selectedStock = appState.statusBarStock
            }
        })
    }
}

private struct StockDropFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
