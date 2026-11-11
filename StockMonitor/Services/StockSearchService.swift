// Created by april on 2026/11/11.
import Foundation

enum StockSearchService {
    struct SearchResult: Identifiable {
        let id: String
        let name: String
        let market: Market
    }

    /// 主搜索：腾讯（A股/港股/美股）和 Yahoo（韩股）并行，结果合并。
    /// 用户输入 6 位数字 / 英文 / 韩文 时，A股 和 同号韩股 会同时显示。
    static func fetchSuggestions(_ keyword: String) async -> [SearchResult] {
        async let tencent = tencentSearch(keyword)
        async let korean  = shouldQueryKorean(keyword)
                            ? yahooKoreanSearch(keyword)
                            : [SearchResult]()
        let (t, k) = await (tencent, korean)

        // 合并：先腾讯结果（保持原有排序），再 Yahoo 韩股结果，去重
        var seen = Set<String>()
        var merged: [SearchResult] = []
        for r in t + k where !seen.contains(r.id) {
            seen.insert(r.id)
            merged.append(r)
        }

        if merged.isEmpty {
            // 全空：新浪兜底（覆盖某些美股 ticker）→ 直接代码兜底
            let sina = await sinaFetchSuggestions(keyword)
            return sina.isEmpty ? directResult(for: keyword) : sina
        }
        return merged
    }

    /// 腾讯搜索（A股/港股/美股），失败返回空。
    private static func tencentSearch(_ keyword: String) async -> [SearchResult] {
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://proxy.finance.qq.com/ifzqgtimg/appstock/smartbox/search/get?q=\(encoded)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let stocks = dataObj["stock"] as? [[String]] else {
            return []
        }
        return stocks.compactMap { item -> SearchResult? in
            guard item.count >= 3 else { return nil }
            let mkt  = item[0].lowercased()
            let code = item[1].lowercased()
            let name = item[2]
            switch mkt {
            case "sh", "sz", "bj": return SearchResult(id: "\(mkt)\(code)", name: name, market: .aStock)
            case "hk":             return SearchResult(id: "hk\(code)",      name: name, market: .hkStock)
            case "us":
                let parts = code.components(separatedBy: ".")
                let ticker = (parts.count > 1 ? parts.dropLast().joined(separator: ".") : code).lowercased()
                return SearchResult(id: "usr_\(ticker)", name: name, market: .usStock)
            default: return nil
            }
        }
    }

    /// 是否同时跑一次 Yahoo 韩股搜索：
    /// - 含 Hangul / 带 .ks/.kq 后缀 / kr_ 前缀 → 一定
    /// - 6 位纯数字（韩股代码长度）→ 一定（即便腾讯能搜到 A 股，同号韩股也想看到）
    /// - 纯字母长度 ≥ 3 → 一定（公司名）
    /// 其它（短数字、特殊字符）跳过 Yahoo，省一次请求
    private static func shouldQueryKorean(_ s: String) -> Bool {
        let k = s.trimmingCharacters(in: .whitespaces)
        let lower = k.lowercased()
        if lower.hasSuffix(".ks") || lower.hasSuffix(".kq") { return true }
        if lower.hasPrefix("kr_") { return true }
        if k.unicodeScalars.contains(where: { $0.value >= 0xAC00 && $0.value <= 0xD7AF }) { return true }
        if k.count == 6, k.allSatisfy(\.isNumber) { return true }
        if k.count >= 3, k.allSatisfy(\.isLetter) { return true }
        return false
    }

    /// Yahoo /v1/finance/search — 仅返回韩股（KSC / KOE 两种 exchange）
    private static func yahooKoreanSearch(_ keyword: String) async -> [SearchResult] {
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://query1.finance.yahoo.com/v1/finance/search?q=\(encoded)&quotesCount=10")
              else {
            return []
        }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let quotes = root["quotes"] as? [[String: Any]] else { return [] }
        return quotes.compactMap { q -> SearchResult? in
            guard (q["quoteType"] as? String) == "EQUITY",
                  let symbol = q["symbol"] as? String else { return nil }
            // 韩股 symbol 以 .KS / .KQ 结尾
            let upper = symbol.uppercased()
            guard upper.hasSuffix(".KS") || upper.hasSuffix(".KQ") else { return nil }
            let id = KoreanStockID.fromYahooSymbol(symbol)
            let name = (q["shortname"] as? String) ?? (q["longname"] as? String) ?? symbol
            return SearchResult(id: id, name: name, market: .krStock)
        }
    }

    /// 新浪 suggest 兜底（主要覆盖美股/期货等腾讯接口不返回的品种）
    private static func sinaFetchSuggestions(_ keyword: String) async -> [SearchResult] {
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://suggest3.sinajs.cn/suggest/type=11,12,13,14&key=\(encoded)"),
              let (data, _) = try? await URLSession.shared.data(from: url) else {
            return directResult(for: keyword)
        }
        let body = StringDecoding.decodeGBK(data)
        guard let s = body.range(of: "\""),
              let e = body.lastIndex(of: "\""),
              e > s.upperBound else { return directResult(for: keyword) }
        let results = String(body[body.index(after: s.lowerBound)..<e])
            .components(separatedBy: ";")
            .filter { !$0.isEmpty }
            .compactMap { item -> SearchResult? in
                let p = item.components(separatedBy: ",")
                guard p.count >= 5 else { return nil }
                let market: Market; let id: String
                switch p[0] {
                case "11", "14": market = .aStock;  id = p[3].lowercased()
                case "12":       market = .hkStock; id = "hk" + p[3].lowercased()
                case "13":       market = .usStock; id = p[3].lowercased()
                default: return nil
                }
                return SearchResult(id: id, name: p[4], market: market)
            }
        return results.isEmpty ? directResult(for: keyword) : results
    }

    /// 将纯数字/字母输入当作直接代码（兜底）：6位数→sh，其余→sz
    private static func directResult(for keyword: String) -> [SearchResult] {
        let k = keyword.lowercased().trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return [] }
        // 已有前缀（sh/sz/bj/hk/usr_）直接使用
        if k.hasPrefix("sh") || k.hasPrefix("sz") || k.hasPrefix("bj") {
            let market: Market = k.hasPrefix("hk") ? .hkStock : .aStock
            return [SearchResult(id: k, name: k.uppercased(), market: market)]
        }
        if k.hasPrefix("hk") {
            return [SearchResult(id: k, name: k.uppercased(), market: .hkStock)]
        }
        if k.hasPrefix("usr_") {
            return [SearchResult(id: k, name: k.uppercased(), market: .usStock)]
        }
        // 韩股：kr_005930.ks / 005930.ks / 005930.kq 形式
        if k.hasPrefix("kr_") {
            return [SearchResult(id: k, name: k.uppercased(), market: .krStock)]
        }
        if k.hasSuffix(".ks") || k.hasSuffix(".kq") {
            return [SearchResult(id: "kr_\(k)", name: k.uppercased(), market: .krStock)]
        }
        // 港股：4-5位纯数字，补齐5位前导零
        if k.allSatisfy(\.isNumber), k.count >= 4, k.count <= 5 {
            let padded = String(repeating: "0", count: 5 - k.count) + k
            return [SearchResult(id: "hk\(padded)", name: k, market: .hkStock)]
        }
        // A股：6位纯数字，0/3开头 → sz（深交所），其余 → sh（沪市）
        if k.allSatisfy(\.isNumber), k.count == 6 {
            let prefix = (k.hasPrefix("0") || k.hasPrefix("3")) ? "sz" : "sh"
            return [SearchResult(id: "\(prefix)\(k)", name: k, market: .aStock)]
        }
        return []
    }

}
