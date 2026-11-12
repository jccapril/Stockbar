import Foundation

enum DisplayCurrency: String, Codable, CaseIterable {
    case cny = "CNY"
    case hkd = "HKD"
    case usd = "USD"
    case krw = "KRW"

    var symbol: String {
        switch self {
        case .cny: "¥"
        case .hkd: "HK$"
        case .usd: "$"
        case .krw: "₩"
        }
    }

    var displayName: String {
        switch self {
        case .cny: "人民币 ¥"
        case .hkd: "港币 HK$"
        case .usd: "美元 $"
        case .krw: "韩元 ₩"
        }
    }
}

enum SortRule: String, Codable, CaseIterable {
    case changeDesc
    case changeAsc

    var displayName: String {
        switch self {
        case .changeDesc: "涨跌幅降序"
        case .changeAsc:  "涨跌幅升序"
        }
    }
}

enum USPriceMode: String, Codable, CaseIterable {
    case sessionPrice = "session"
    case regularPrice = "regular"

    var displayName: String {
        switch self {
        case .sessionPrice: "当前价（时段价格）"
        case .regularPrice: "盘中价"
        }
    }
}

enum ColorTheme: String, Codable, CaseIterable {
    case chinese  // 红涨绿跌
    case western  // 绿涨红跌

    var displayName: String {
        switch self {
        case .chinese: "红涨绿跌"
        case .western: "绿涨红跌"
        }
    }
}

enum StatusBarQuoteDisplay: String, Codable, CaseIterable {
    case price
    case percent
    case priceAndPercent

    var displayName: String {
        switch self {
        case .price: "仅价格"
        case .percent: "仅涨跌幅"
        case .priceAndPercent: "价格 + 涨跌幅"
        }
    }
}

struct AppSettings {
    var aiAPIAddress = ""
    var aiModel = ""
    var statusBarStockId: String         = ""
    var statusBarQuoteDisplay: StatusBarQuoteDisplay = .price
    var statusBarRotationEnabled = false
    var statusBarRotationInterval = 5
    var refreshInterval: Int             = 5
    var colorScheme: ColorTheme          = .chinese
    var displayCurrency: DisplayCurrency = .cny
    var sortRule: SortRule               = .changeDesc
    var usPriceMode: USPriceMode         = .sessionPrice
    var showListSearch = true
    var showOverseasIndices = true
    var groupHoldings: Bool              = false

    static let validRefreshIntervals = [3, 5, 10, 30]
    static let validRotationIntervals = [3, 5, 10, 15, 30, 60]

    var upColorName: String   { colorScheme == .chinese ? "upRed"   : "upGreen" }
    var downColorName: String { colorScheme == .chinese ? "downGreen" : "downRed" }
}

// MARK: - Codable（容错：缺失字段使用默认值）
extension AppSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case aiAPIAddress, aiModel
        case showListSearch, showOverseasIndices
        case statusBarQuoteDisplay
        case statusBarRotationEnabled, statusBarRotationInterval
        case statusBarStockId, refreshInterval, colorScheme, displayCurrency, sortRule, usPriceMode, groupHoldings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aiAPIAddress = try c.decodeIfPresent(String.self, forKey: .aiAPIAddress) ?? ""
        aiModel = try c.decodeIfPresent(String.self, forKey: .aiModel) ?? ""
        showListSearch = try c.decodeIfPresent(Bool.self, forKey: .showListSearch) ?? true
        showOverseasIndices = try c.decodeIfPresent(Bool.self, forKey: .showOverseasIndices) ?? true
        statusBarRotationEnabled = try c.decodeIfPresent(Bool.self, forKey: .statusBarRotationEnabled) ?? false
        let rotationInterval = try c.decodeIfPresent(Int.self, forKey: .statusBarRotationInterval) ?? 5
        statusBarRotationInterval = Self.validRotationIntervals.contains(rotationInterval) ? rotationInterval : 5
        statusBarQuoteDisplay = (try? c.decodeIfPresent(StatusBarQuoteDisplay.self, forKey: .statusBarQuoteDisplay)) ??
            .price
        statusBarStockId   = (try? c.decodeIfPresent(String.self,          forKey: .statusBarStockId))    ?? ""
        refreshInterval    = (try? c.decodeIfPresent(Int.self,             forKey: .refreshInterval))     ?? 5
        colorScheme        = (try? c.decodeIfPresent(ColorTheme.self,      forKey: .colorScheme))         ?? .chinese
        displayCurrency    = (try? c.decodeIfPresent(DisplayCurrency.self, forKey: .displayCurrency))     ?? .cny
        sortRule           = (try? c.decodeIfPresent(SortRule.self,         forKey: .sortRule))            ??
            .changeDesc
        usPriceMode        = (try? c.decodeIfPresent(USPriceMode.self,     forKey: .usPriceMode))         ??
            .sessionPrice
        groupHoldings      = (try? c.decodeIfPresent(Bool.self,            forKey: .groupHoldings))       ?? false
    }
}
