// Created by april on 2026/11/11.
import Foundation

extension ChartService {
    static func fetchCandles(stock: Stock, period: CandlePeriod) async throws -> [CandlePoint] {
        let yahoo = stock.yahooChartSymbol != nil
        let urlString: String
        if yahoo {
            guard let symbol = stock.yahooChartSymbol else { throw URLError(.badURL) }
            let years = period == .daily ? 2 : period == .weekly ? 5 : 20
            let end = Int(Date().timeIntervalSince1970)
            let start = end - years * 366 * 86400
            urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=\(period.yahooInterval)&period1=\(start)&period2=\(end)"
        } else {
            urlString = "https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param=\(stock.id),\(period.rawValue),,,240,"
        }
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try yahoo ? parseYahooCandles(data, period: period) : parseTencentCandles(
            data,
            code: stock.id,
            period: period,
        )
    }

    static func parseTencentCandles(_ data: Data, code: String, period: CandlePeriod) throws -> [CandlePoint] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any], let item = payload[code] as? [String: Any],
              let rows = item[period.rawValue] as? [[Any]] else { throw URLError(.cannotParseResponse) }
        var bars: [CandlePoint] = []
        for row in rows {
            // 腾讯字段顺序为日期、开、收、高、低；港股尾部还可能有公司行动对象。
            guard row.count >= 5, let date = row[0] as? String,
                  let openText = row[1] as? String, let open = Double(openText),
                  let closeText = row[2] as? String, let close = Double(closeText),
                  let highText = row[3] as? String, let high = Double(highText),
                  let lowText = row[4] as? String, let low = Double(lowText) else { continue }
            bars.append(CandlePoint(date: date, open: open, close: close, high: high, low: low))
        }
        return try normalizeCandles(bars, period: period)
    }

    static func parseYahooCandles(_ data: Data, period: CandlePeriod) throws -> [CandlePoint] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = root["chart"] as? [String: Any], let results = chart["result"] as? [[String: Any]],
              let result = results.first, let meta = result["meta"] as? [String: Any],
              meta["dataGranularity"] as? String == period.yahooInterval,
              let zone = meta["exchangeTimezoneName"] as? String, let timeZone = TimeZone(identifier: zone),
              let timestamps = result["timestamp"] as? [Double],
              let indicators = result["indicators"] as? [String: Any],
              let quotes = indicators["quote"] as? [[String: Any]], let quote = quotes.first,
              let opens = quote["open"] as? [Any], let closes = quote["close"] as? [Any],
              let highs = quote["high"] as? [Any], let lows = quote["low"] as? [Any],
              [opens.count, closes.count, highs.count, lows.count].allSatisfy({ $0 == timestamps.count })
        else { throw URLError(.cannotParseResponse) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var bars: [CandlePoint] = []
        for index in timestamps.indices {
            // 空采样不能画为零价 K 线。
            guard let open = opens[index] as? Double, let close = closes[index] as? Double,
                  let high = highs[index] as? Double, let low = lows[index] as? Double,
                  timestamps[index].isFinite else { continue }
            let date = formatter.string(from: Date(timeIntervalSince1970: timestamps[index]))
            bars.append(CandlePoint(date: date, open: open, close: close, high: high, low: low))
        }
        return try normalizeCandles(bars, period: period)
    }

    private static func normalizeCandles(_ bars: [CandlePoint], period: CandlePeriod) throws -> [CandlePoint] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        var grouped: [String: CandlePoint] = [:]
        for bar in bars.sorted(by: { $0.date < $1.date }) {
            guard [bar.open, bar.close, bar.high, bar.low].allSatisfy({ $0.isFinite && $0 > 0 }),
                  bar.high >= max(bar.open, bar.close), bar.low <= min(bar.open, bar.close),
                  let date = formatter.date(from: bar.date) else { continue }
            let start: Date = switch period {
            case .daily: date
            case .weekly: calendar.dateInterval(of: .weekOfYear, for: date)!.start
            case .monthly: calendar.dateInterval(of: .month, for: date)!.start
            }
            let key = formatter.string(from: start)
            // Yahoo 可能在周/月汇总后附加当日快照，合并同周期而非多画一根。
            let previous = grouped[key]
            grouped[key] = CandlePoint(
                date: key,
                open: previous?.open ?? bar.open,
                close: bar.close,
                high: max(previous?.high ?? bar.high, bar.high),
                low: min(previous?.low ?? bar.low, bar.low),
            )
        }
        var result: [CandlePoint] = []
        for key in grouped.keys.sorted() {
            var bar = grouped[key]!
            bar.previousClose = result.last?.close
            result.append(bar)
        }
        guard !result.isEmpty else { throw URLError(.cannotParseResponse) }
        return Array(result.suffix(240))
    }
}
