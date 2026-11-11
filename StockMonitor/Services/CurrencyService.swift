import Foundation

struct ExchangeRates {
    var usdToCny: Double = 7.28      // 默认兜底值
    var usdToHkd: Double = 7.78
    var usdToKrw: Double = 1380.0    // 默认兜底（2026 年初均值）；CurrencyService 拉成功后覆盖

    /// HKD/CNY = USD/CNY ÷ USD/HKD
    var hkdToCny: Double { usdToCny / usdToHkd }
    /// KRW/CNY = USD/CNY ÷ USD/KRW
    var krwToCny: Double { usdToCny / usdToKrw }

    /// 将 amount（native 货币）转换为目标货币
    func convert(_ amount: Double, from market: Market, to currency: DisplayCurrency) -> Double {
        // 先统一转成 CNY
        let inCny: Double
        switch market {
        case .index: return amount // 指数是点数，不参与汇率换算。
        case .aStock:  inCny = amount
        case .hkStock: inCny = amount * hkdToCny
        case .usStock: inCny = amount * usdToCny
        case .krStock: inCny = amount * krwToCny
        }
        // 再从 CNY 转出去
        switch currency {
        case .cny: return inCny
        case .hkd: return inCny / hkdToCny
        case .usd: return inCny / usdToCny
        case .krw: return inCny / krwToCny
        }
    }
}

enum CurrencyService {

    /// 从新浪财经获取 USD/CNY、USD/HKD、USD/KRW 汇率，失败时返回内置兜底值
    static func fetchRates() async -> ExchangeRates {
        let urlStr = "https://hq.sinajs.cn/list=fx_susdcny,fx_susdhkd,fx_susdkrw"
        guard let url = URL(string: urlStr) else { return ExchangeRates() }
        var req = URLRequest(url: url)
        req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")

        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return ExchangeRates() }
        let body = StringDecoding.decodeGBK(data)

        var rates = ExchangeRates()
        for line in body.components(separatedBy: "\n") {
            if let r = parseFirstPositiveDouble(from: line, code: "fx_susdcny") { rates.usdToCny = r }
            if let r = parseFirstPositiveDouble(from: line, code: "fx_susdhkd") { rates.usdToHkd = r }
            if let r = parseFirstPositiveDouble(from: line, code: "fx_susdkrw") { rates.usdToKrw = r }
        }
        return rates
    }

    /// 从 `var hq_str_{code}="..."` 中提取第一个正 Double
    private static func parseFirstPositiveDouble(from line: String, code: String) -> Double? {
        guard line.contains(code),
              let s = line.firstIndex(of: "\""),
              let e = line.lastIndex(of: "\""),
              e > s else { return nil }
        let content = String(line[line.index(after: s)..<e])
        return content
            .components(separatedBy: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            .first { $0 > 0 }
    }
}
