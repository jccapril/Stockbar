// Created by april on 2026/11/12.
import CoreGraphics
import Foundation

extension AppState {
    func assignStock(_ stockID: String, to groupID: String?) {
        // 股票可能已在另一个窗口被删除，按当前数据定位。
        guard let index = stocks.firstIndex(where: { $0.id == stockID }) else { return }
        stocks[index].customGroupID = groupID
    }

    func deleteStockGroup(_ groupID: String) {
        var updated = stocks
        for index in updated.indices where updated[index].customGroupID == groupID {
            updated[index].customGroupID = nil
        }
        stocks = updated
        config.customStockGroups.removeAll { $0.id == groupID }
    }

    func stockDropPlacement(
        for stock: Stock, at location: CGPoint, groups: [StockListGroup],
        dropFrames: [String: CGRect], rowFrames: [String: CGRect],
    ) -> (pinned: Bool, groupID: String?, index: Int, lineY: CGFloat?)? {
        // 列表外松手取消移动；置顶不改变原有自定义分组归属。
        guard dropFrames["list"]?.contains(location) == true else { return nil }
        let pinned = dropFrames["pinned"]?.contains(location) == true
        let targetGroup = config.customStockGroups.first {
            dropFrames["group:\($0.id)"]?.contains(location) == true
        }
        let groupID = pinned ? stock.customGroupID : targetGroup?.id
        let ordered = groups.flatMap(\.1).filter { $0.id != stock.id }
        let isHolding = config.groupHoldings && stock.holdingShares != nil
        let knownIDs = Set(config.customStockGroups.map(\.id))
        let candidates = ordered.filter { candidate in
            if pinned { return candidate.isPinned }
            if candidate.isPinned { return false }
            if let groupID { return candidate.customGroupID == groupID }
            if knownIDs.contains(candidate.customGroupID ?? "") { return false }
            let candidateHolding = config.groupHoldings && candidate.holdingShares != nil
            return isHolding ? candidateHolding : !candidateHolding && candidate.market == stock.market
        }
        if let next = candidates.first(where: { candidate in
            rowFrames[candidate.id].map { location.y < $0.midY } ?? false
        }), let index = ordered.firstIndex(where: { $0.id == next.id }) {
            return (pinned, groupID, index, rowFrames[next.id].map { $0.minY - 1 })
        }
        if let last = candidates.last, let index = ordered.firstIndex(where: { $0.id == last.id }) {
            return (pinned, groupID, index + 1, rowFrames[last.id].map { $0.maxY + 1 })
        }
        // 空分组仍有明确落点，让提示线和松手结果一致。
        let frame = pinned ? dropFrames["pinned"] : targetGroup.flatMap { dropFrames["group:\($0.id)"] }
            ?? dropFrames["unpinnedEmpty"] ?? rowFrames[stock.id]
        return (pinned, groupID, ordered.count, frame?.midY)
    }
}
