// Created by april on 2026/11/12.
import Foundation

extension AppState {
    /// 分组数据：(market, stocks, customTitle?)
    func groupedStocks(searchQuery: String = "") -> [(Market, [Stock], String?)] {
        let rule = config.sortRule
        let usMode = config.usPriceMode
        let doSort = sortByChange

        func sorted(_ stocks: [Stock], market: Market) -> [Stock] {
            guard doSort else { return stocks }
            return stocks.sorted { a, b in
                let va = sortValue(quote: quotes[a.id], market: market, mode: usMode)
                let vb = sortValue(quote: quotes[b.id], market: market, mode: usMode)
                return rule == .changeDesc ? va > vb : va < vb
            }
        }

        var result: [(Market, [Stock], String?)] = []
        let indexIDs = Set(AppState.marketIndices.map(\.id))
        let listStocks = stocks.filter { !indexIDs.contains($0.id) && $0.matchesListSearch(searchQuery) }
        let pinnedStocks = listStocks.filter(\.isPinned)
        let unpinnedStocks = listStocks.filter { !$0.isPinned }

        // 置顶组独立于市场和持仓分组，涨跌幅排序不会把它移到下方。
        if !pinnedStocks.isEmpty {
            result.append((.aStock, pinnedStocks, "置顶"))
        }

        // 持仓股单独分组
        if config.groupHoldings {
            let holdings = unpinnedStocks.filter { $0.holdingShares != nil }
            if !holdings.isEmpty {
                // 持仓组内按第一只股票的市场类型排序（混合市场）
                let sortedHoldings = doSort ? holdings.sorted { a, b in
                    let va = sortValue(quote: quotes[a.id], market: a.market, mode: usMode)
                    let vb = sortValue(quote: quotes[b.id], market: b.market, mode: usMode)
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

    private func sortValue(quote: Quote?, market: Market, mode: USPriceMode) -> Double {
        guard let q = quote else { return -Double.infinity }
        if market == .usStock, mode == .sessionPrice, let ext = q.extendedPrice {
            // 用时段价格算涨跌幅：(盘外价 - 正盘价) / 正盘价
            return q.price > 0 ? (ext - q.price) / q.price * 100 : q.changePercent
        }
        return q.changePercent
    }

}
