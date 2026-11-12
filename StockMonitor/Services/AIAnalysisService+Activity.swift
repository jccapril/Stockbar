// Created by april on 2026/11/12.
import Foundation

extension AIAnalysisService {
    struct Activity {
        let quote: Quote
        let volumeUnit: String
        let volume: Double?
        let amount: Double?
        let turnoverPercent: Double?
        let volumeRatio: Double?

        var payload: [String: Any] {
            var value: [String: Any] = [
                "source": "Tencent qt.gtimg.cn", "time": quote.updateTime,
                "timeZone": "Asia/Shanghai", "volumeUnit": volumeUnit, "amountCurrency": "CNY",
                "scope": "当日累计，可能为未收盘数据",
            ]
            value["volume"] = volume
            value["amount"] = amount
            value["turnoverPercent"] = turnoverPercent
            value["volumeRatio"] = volumeRatio
            return value
        }
    }

    static func fetchActivity(stock: Stock) async throws -> Activity? {
        // 首版仅使用已核对的 A 股和 ETF 字段；其他市场不套用相同位置和单位。
        guard stock.market == .aStock else { return nil }
        var components = URLComponents(string: "https://qt.gtimg.cn/")!
        components.queryItems = [URLQueryItem(name: "q", value: stock.id)]
        let request = URLRequest(url: components.url!, timeoutInterval: 20)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure(message: "成交数据获取失败，请稍后重试。")
        }
        return try parseActivity(StringDecoding.decodeGBK(data), code: stock.id)
    }

    static func parseActivity(_ body: String, code: String) throws -> Activity? {
        guard let line = body.components(separatedBy: "\n").first(where: { $0.hasPrefix("v_\(code)=\"") }),
              let start = line.range(of: "=\""), let end = line.lastIndex(of: "\""), end >= start.upperBound else {
            throw Failure(message: "成交数据响应无效。")
        }
        let fields = String(line[start.upperBound..<end]).components(separatedBy: "~")
        guard fields.count > 61 else { throw Failure(message: "成交数据字段不完整。") }
        // 中国指数等品种没有核对过换手率与份额口径，不向模型提供这些字段。
        guard fields[61] == "GP-A" || fields[61] == "ETF" else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.isLenient = false
        guard let date = formatter.date(from: fields[30]),
              let price = Double(fields[3]), price.isFinite, price > 0,
              let previousClose = Double(fields[4]), previousClose.isFinite, previousClose > 0 else {
            throw Failure(message: "成交行情的价格或时间无效。")
        }
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        // 外部接口中的空值、负数、非数均省略；有效的零成交量仍保留。
        let value: (Int) -> Double? = { index in
            guard let number = Double(fields[index]), number.isFinite, number >= 0 else { return nil }
            return number
        }
        return Activity(
            quote: Quote(
                code: code,
                name: fields[1],
                price: price,
                change: price - previousClose,
                changePercent: (price / previousClose - 1) * 100,
                updateTime: formatter.string(from: date),
            ),
            volumeUnit: fields[61] == "ETF" ? "份" : "股",
            volume: value(6).map { $0 * 100 },
            amount: value(57).map { $0 * 10000 },
            turnoverPercent: value(38), volumeRatio: value(49),
        )
    }
}
