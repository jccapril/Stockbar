import SwiftUI

struct DropdownView: View {
    @EnvironmentObject var appState: AppState
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

    private var groupedStocks: [StockListGroup] {
        appState.groupedStocks(searchQuery: searchQuery)
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
                    let targetKey = group.3.map { "group:\($0)" } ?? (group.2 == "置顶" ? "pinned" : "")
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
                            if group.2 == "置顶" || group.3 != nil {
                                Color.clear.preference(
                                    key: StockDropFramesKey.self,
                                    value: [group.3.map { "group:\($0)" } ?? "pinned": geometry
                                    .frame(in: .named("stockList"))],
                                )
                            }
                        })
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(dragLocation.map { dropFrames[targetKey]?.contains($0) == true } == true ? Color
                                .accentColor : .clear)
                            .allowsHitTesting(false))
                }
                // 全部股票都置顶时，也留出可以拖回普通列表的落点。
                if groups.contains(where: { $0.2 == "置顶" || $0.3 != nil }) {
                    Label("拖到这里恢复默认分组", systemImage: "folder")
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

    private func dropPlacement(
        for stock: Stock,
        at location: CGPoint,
    ) -> (pinned: Bool, groupID: String?, index: Int, lineY: CGFloat?)? {
        appState.stockDropPlacement(
            for: stock,
            at: location,
            groups: groupedStocks,
            dropFrames: dropFrames,
            rowFrames: rowFrames,
        )
    }

    private func moveStock(_ stock: Stock, at location: CGPoint) {
        guard let placement = dropPlacement(for: stock, at: location) else { return }
        var moved = stock
        moved.isPinned = placement.pinned
        moved.customGroupID = placement.groupID
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
        appState.sortByChange = false
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
            ToolbarView(sortByChange: $appState.sortByChange)
        }
        .padding(6)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(StatusPanelObserver(theme: appState.config.theme) { focused in
            let wasOpen = appState.isStatusPanelOpen
            appState.isStatusPanelOpen = focused
            // 每次打开快照一次，随后保留用户的返回列表、切换股票等操作。
            if focused, !wasOpen, appState.isStatusBarRotating {
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
