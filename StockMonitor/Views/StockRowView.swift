import SwiftUI

struct StockRowView: View {
    let stock: Stock
    let quote: Quote?
    var onTap: (() -> Void)?
    var onReorderDragChanged: (DragGesture.Value) -> Void
    var onReorderDragEnded: (CGPoint) -> Void
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 在菜单栏面板内部确认，避免独立弹框使面板失去焦点并关闭。
            if showDeleteConfirmation {
                Text("删除\(stock.name)？")
                    .font(.system(size: 12, weight: .medium))
                Text("将移除该股票及其真实持仓信息。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Spacer()
                    Button("取消") { showDeleteConfirmation = false }
                    Button("确认删除", role: .destructive) {
                        appState.stocks.removeAll { $0.id == stock.id }
                        // 删除状态栏正在展示的股票后，恢复自动选择。
                        if appState.statusBarStockId == stock.id { appState.statusBarStockId = "" }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                stockContent
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(4)
    }

    private var stockContent: some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 16, height: 24)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("stockList"))
                    .onChanged(onReorderDragChanged)
                    .onEnded { onReorderDragEnded($0.location) })
                .help("拖动排序，拖入或拖出置顶区域可切换置顶")
                .accessibilityLabel("拖动排序\(stock.name)")

            quoteContent
                .contentShape(Rectangle())
                .onTapGesture { onTap?() }

            Menu {
                Button {
                    appState.selectedAlertStock = stock
                    openWindow(id: "price-alerts")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("价格提醒", systemImage: "bell")
                }
                Button {
                    appState.stocks = appState.stocks.map { item in
                        var updated = item
                        // 只更新当前行，保留其他股票的顺序和持仓信息。
                        if item.id == stock.id { updated.isPinned.toggle() }
                        return updated
                    }
                } label: {
                    Label(
                        stock.isPinned ? "取消置顶" : "置顶",
                        systemImage: stock.isPinned ? "pin.slash" : "pin",
                    )
                }
                Divider()
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 20, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("股票操作")
            .accessibilityLabel("\(stock.name)的操作")
        }
    }

    private var quoteContent: some View {
        HStack(alignment: .center, spacing: 0) {
            // 左侧：名称 + 代码
            VStack(alignment: .leading, spacing: 1) {
                Text(stock.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(stock.id)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 4)
            // 右侧：行情 + 盈亏
            if let q = quote {
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(q.formattedPrice)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(appState.quoteColor(for: q))
                        Text(q.formattedPercent)
                            .font(.system(size: 11))
                            .foregroundColor(appState.quoteColor(for: q))
                    }
                    if stock.market == .usStock,
                       let session = AppState.usMarketSession(),
                       let extPrice = q.formattedExtendedPrice,
                       let extPct = q.formattedExtendedPercent {
                        Text("\(session) \(extPrice)  \(extPct)")
                            .font(.system(size: 9))
                            .foregroundColor(
                                (q.extendedChangePercent ?? 0) >= 0
                                    ? Color(appState.config.upColorName)
                                    : Color(appState.config.downColorName),
                            )
                    }
                    if appState.effectiveShares(for: stock) == nil {
                        Text("未持仓")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 4) {
                            if let daily = appState.effectiveDailyPnl(stock: stock, quote: q) {
                                Text(daily >= 0
                                     ? "日+\(String(format: "%.2f", daily))"
                                     :  "日\(String(format: "%.2f", daily))")
                                    .font(.system(size: 10))
                                    .foregroundColor(appState.pnlColor(daily))
                            }
                            if let pnl = appState.effectivePnl(stock: stock, quote: q) {
                                let pct = appState.effectivePnlPercent(stock: stock, quote: q)
                                let pctStr = pct.map { String(format: " %.2f%%", $0) } ?? ""
                                Text(pnl >= 0
                                     ? "浮+\(String(format: "%.2f", pnl))\(pctStr)"
                                     :  "浮\(String(format: "%.2f", pnl))\(pctStr)")
                                    .font(.system(size: 10))
                                    .foregroundColor(appState.pnlColor(pnl))
                            }
                        }
                    }
                }
            } else {
                Text("--")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
            }
        }
    }
}
