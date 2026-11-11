import Foundation

enum Market: String, Codable, CaseIterable {
    case aStock  = "A股"
    case hkStock = "港股"
    case usStock = "美股"
    case krStock = "韩股"
    case index = "指数"

    static func from(code: String) -> Market {
        if code.hasPrefix("hk")   { return .hkStock }
        if code.hasPrefix("usr_") { return .usStock }
        if code.hasPrefix("kr_")  { return .krStock }
        return .aStock
    }
}

struct Stock: Identifiable, Equatable {
    var id: String              // 股票代码，如 "sh600000"、"usr_aapl"、"hk00700"
    var name: String
    var market: Market
    var costPrice: Double?      // 持仓成本价（nil = 未设置）
    var holdingShares: Double?  // 持仓股数（nil = 未设置）
    var isPinned: Bool = false

    var yahooChartSymbol: String? {
        switch market {
        case .index: id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        case .krStock: KoreanStockID.toYahooSymbol(id)
        case .usStock: id.replacingOccurrences(of: "usr_", with: "").replacingOccurrences(of: "$", with: "-")
            .uppercased()
        case .aStock, .hkStock: nil
        }
    }

    func matchesListSearch(_ query: String) -> Bool {
        query.isEmpty || name.localizedStandardContains(query) || id.localizedStandardContains(query)
    }

    /// 持仓浮盈亏 = (当前价 - 成本价) × 股数；未设置持仓则返回 nil
    func pnl(quote: Quote) -> Double? {
        guard let cost = costPrice, let shares = holdingShares else { return nil }
        return (quote.price - cost) * shares
    }

    /// 当日盈亏 = 涨跌额 × 股数；未设置股数则返回 nil
    func dailyPnl(quote: Quote) -> Double? {
        guard let shares = holdingShares else { return nil }
        return quote.change * shares
    }

    /// 浮盈亏百分比 = (现价 - 成本价) / 成本价 × 100
    func pnlPercent(quote: Quote) -> Double? {
        guard let cost = costPrice, cost > 0 else { return nil }
        return (quote.price - cost) / cost * 100
    }

    /// 当日盈亏百分比 = 涨跌额 / 成本价 × 100
    func dailyPnlPercent(quote: Quote) -> Double? {
        guard let cost = costPrice, cost > 0 else { return nil }
        return quote.change / cost * 100
    }
}

// MARK: - Codable（容错：未知字段用默认值，避免新版本解码老数据时整条失败）
extension Stock: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, market, costPrice, holdingShares, isPinned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(String.self,  forKey: .id)
        name         = try c.decode(String.self,  forKey: .name)
        market       = try c.decode(Market.self,  forKey: .market)
        costPrice    = try c.decodeIfPresent(Double.self, forKey: .costPrice)
        holdingShares = try c.decodeIfPresent(Double.self, forKey: .holdingShares)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}

/// 顶部指数的固定市场分组，不加入用户自选股列表。
enum IndexMarket: String, CaseIterable {
    case china = "A股"
    case korea = "韩国"
    case japan = "日本"
    case unitedStates = "美国"

    var stocks: [Stock] {
        let items: [(String, String)] = switch self {
        case .china: [("sh000001", "上证"), ("sz399006", "创业"), ("sh000688", "科创")]
        case .korea: [("^KS11", "KOSPI")]
        case .japan: [("^N225", "日经225")]
        case .unitedStates: [("^DJI", "道琼斯"), ("^IXIC", "纳斯达克"), ("^GSPC", "标普500")]
        }
        return items.map { Stock(id: $0.0, name: $0.1, market: self == .china ? .aStock : .index) }
    }
}
