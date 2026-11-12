// Created by april on 2026/11/12.
import SwiftUI

struct SettingsStockListView: View {
    var onEdit: (Stock) -> Void
    @EnvironmentObject var appState: AppState
    @State private var draggedStock: Stock?
    @State private var dragLocation: CGPoint?
    @State private var dragTranslation: CGFloat = 0
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var dropFrames: [String: CGRect] = [:]
    @Namespace private var dragSpace

    private var isPinTargeted: Bool {
        dragLocation.map { dropFrames["pinned"]?.contains($0) == true } ?? false
    }

    var body: some View {
        let groups = appState.groupedStocks()
        VStack(alignment: .leading, spacing: 12) {
            if !groups.contains(where: { $0.2 == "置顶" }) {
                Label("拖到这里置顶", systemImage: "pin")
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(
                        Color.accentColor.opacity(isPinTargeted ? 0.18 : 0.04),
                        in: RoundedRectangle(cornerRadius: 6),
                    )
                    .background(dropFrame("pinned"))
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.2 ?? group.0.rawValue)
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    ForEach(group.1) { stock in draggableRow(stock) }
                }
                .padding(.vertical, 4)
                .background {
                    if group.2 == "置顶" { dropFrame("pinned") }
                }
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(group.2 == "置顶" && isPinTargeted ? Color.accentColor : .clear)
                    .allowsHitTesting(false))
                .zIndex(group.1.contains { $0.id == draggedStock?.id } ? 1 : 0)
            }
            if groups.contains(where: { $0.2 == "置顶" }) {
                Label("拖到这里取消置顶", systemImage: "pin.slash")
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    .background(dropFrame("unpinnedEmpty"))
            }
        }
        .background(dropFrame("list"))
        .overlay(alignment: .topLeading) {
            if let stock = draggedStock, let location = dragLocation,
               let placement = dropPlacement(for: stock, at: location), let y = placement.lineY {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .offset(y: y)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: dragSpace)
        .onPreferenceChange(SettingsStockDropFramesKey.self) { dropFrames = $0 }
        .onPreferenceChange(StockRowFramesKey.self) { frames in
            // 固定拖动起点的行坐标，避免行随手势偏移时影响落点判断。
            if draggedStock == nil { rowFrames = frames }
        }
    }

    private func dropFrame(_ key: String) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: SettingsStockDropFramesKey.self,
                value: [key: geometry.frame(in: .named(dragSpace))],
            )
        }
    }

    private func draggableRow(_ stock: Stock) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 36)
                .contentShape(Rectangle())
                .help("拖动排序，拖入或拖出置顶区域可切换置顶")
                .accessibilityLabel("拖动排序\(stock.name)")
                .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named(dragSpace))
                    .onChanged { value in
                        draggedStock = stock
                        dragLocation = value.location
                        dragTranslation = value.translation.height
                    }
                    .onEnded { value in
                        moveStock(stock, at: value.location)
                        draggedStock = nil
                        dragLocation = nil
                        dragTranslation = 0
                    })
            stockRow(stock)
        }
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .background(GeometryReader { geometry in
            Color.clear.preference(
                key: StockRowFramesKey.self,
                value: [stock.id: geometry.frame(in: .named(dragSpace))],
            )
        })
        .offset(y: draggedStock?.id == stock.id ? dragTranslation : 0)
        .zIndex(draggedStock?.id == stock.id ? 1 : 0)
        .opacity(draggedStock?.id == stock.id ? 0.6 : 1)
    }

    private func dropPlacement(for stock: Stock, at location: CGPoint) -> (pinned: Bool, index: Int, lineY: CGFloat?)? {
        // 松手和提示线共用落点规则，面板外不显示提示、不执行移动。
        guard dropFrames["list"]?.contains(location) == true else { return nil }
        let pinned = dropFrames["pinned"]?.contains(location) == true
        let ordered = appState.groupedStocks().flatMap(\.1).filter { $0.id != stock.id }
        let isHoldingGroup = appState.config.groupHoldings && stock.holdingShares != nil
        let candidates = ordered.filter { candidate in
            // 置顶组可跨市场；取消置顶后遵循原有持仓和市场分组规则。
            if pinned { return candidate.isPinned }
            if candidate.isPinned { return false }
            let candidateIsHolding = appState.config.groupHoldings && candidate.holdingShares != nil
            return isHoldingGroup ? candidateIsHolding : !candidateIsHolding && candidate.market == stock.market
        }
        let next = candidates.first { candidate in
            // 按目标行的上半区或下半区决定插入位置。
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
        let frame = pinned ? dropFrames["pinned"] : dropFrames["unpinnedEmpty"] ?? rowFrames[stock.id]
        return (pinned, ordered.count, frame?.midY)
    }

    private func moveStock(_ stock: Stock, at location: CGPoint) {
        guard let placement = dropPlacement(for: stock, at: location) else { return }
        var moved = stock
        moved.isPinned = placement.pinned
        var ordered = appState.groupedStocks().flatMap(\.1).filter { $0.id != stock.id }
        ordered.insert(moved, at: placement.index)

        // 保存列表顺序，保留不参与列表排序的固定指数。
        let visibleIDs = Set(ordered.map(\.id))
        var updated = appState.stocks
        let positions = updated.indices.filter { visibleIDs.contains(updated[$0].id) }
        for (position, item) in zip(positions, ordered) {
            updated[position] = item
        }
        appState.stocks = updated
        appState.sortByChange = false
    }

    @ViewBuilder
    private func stockRow(_ stock: Stock) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(stock.name).font(.system(size: 12))
                if let c = stock.costPrice,
                   let sh = stock.holdingShares {
                    Text("成本 \(String(format: "%.3f", c)) × \(String(format: "%.0f", sh)) 股")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text("未设置持仓").font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            Button {
                // 操作当前列表中的股票，直接持久化置顶状态。
                if let index = appState.stocks.firstIndex(where: { $0.id == stock.id }) {
                    appState.stocks[index].isPinned.toggle()
                }
            } label: {
                Image(systemName: stock.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(stock.isPinned ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(stock.isPinned ? "取消置顶" : "置顶")
            .accessibilityLabel(stock.isPinned ? "取消置顶" : "置顶")
            Button {
                onEdit(stock)
            } label: { Image(systemName: "pencil").font(.system(size: 11)) }
            .buttonStyle(.plain)

            Button {
                appState.stocks.removeAll { $0.id == stock.id }
                if appState.statusBarStockId == stock.id { appState.statusBarStockId = "" }
            } label: { Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(.red) }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

}

private struct SettingsStockDropFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
