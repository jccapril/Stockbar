// Created by april on 2026/11/11.
import Foundation
import Testing
@testable import Stockbar

@MainActor
struct AIAnalysisPrivacyTests {
    @Test
    func requestContainsOnlyPublicMarketData() throws {
        let stock = Stock(
            id: "sh600000",
            name: "测试股票",
            market: .aStock,
            costPrice: 9876.543,
            holdingShares: 123_456,
            isPinned: true,
        )
        let quote = Quote(code: stock.id, price: 10, change: 1, changePercent: 11.11, updateTime: "2026-11-11 15:00:00")
        let candle = CandlePoint(date: "2026-11-11", open: 9, close: 10, high: 11, low: 8)
        let text = try AIAnalysisService.marketData(stock: stock, quote: quote, candles: [candle], horizon: "短线")
        let payload = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(Set(payload.keys) == ["symbol", "name", "market", "horizon", "requestedAt", "dailyCandles", "quote"])
        #expect(!text.contains("9876.543"))
        #expect(!text.contains("123456"))
        let quoted = try #require(payload["quote"] as? [String: Any])
        #expect(quoted["time"] as? String == quote.updateTime)
        #expect(try AIAnalysisService.endpoint("https://example.com/v1/")
            .absoluteString == "https://example.com/v1/chat/completions")
        #expect(throws: AIAnalysisService.Failure.self) { try AIAnalysisService.endpoint("http://example.com/v1") }
    }

    @Test
    func activityUsesVerifiedUnitsAndOmitsMissingFields() throws {
        let response = #"v_sh588170="1~科创半导体ETF华夏~588170~0.744~0.723~0.721~110928839~58972051~51956788~0.743~4213~0.742~61772~0.741~40629~0.740~72171~0.739~51502~0.744~30312~0.745~48741~0.746~17069~0.747~17005~0.748~25963~~20261112115440~0.021~2.90~0.770~0.717~0.744/110928839/8312098960~110928839~831210~17.87~~~0.770~0.717~7.33~461.74~461.74~0.00~0.868~0.578~1.64~91197~0.749~~~~~~831209.8960~0.0000~0~   A~ETF~48.21~2.20~~~~1.465~0.438~18.47~-11.22~-28.46~62061447000~62061447000~24.69~25.68~62061447000~0.42~0.7409~53.09~0.54~0.7215~CNY~0~___D__F__N~0.735~357633~";"#
        let snapshot = try #require(try AIAnalysisService.parseActivity(response, code: "sh588170"))
        #expect(snapshot.volume == 11_092_883_900)
        let amount = try #require(snapshot.amount)
        #expect(abs(amount - 8_312_098_960) < 0.01)
        #expect(snapshot.turnoverPercent == 17.87)
        #expect(snapshot.volumeRatio == 1.64)
        #expect(snapshot.volumeUnit == "份")
        let candleData = Data(
            #"{"data": {"sh588170": {"day": [["2026-11-05", "0.663", "0.728", "0.747", "0.663", "206589395.000"], ["2026-11-06", "0.687", "0.701", "0.733", "0.680", "166518985.000"], ["2026-11-09", "0.712", "0.697", "0.718", "0.691", "83927056.000"], ["2026-11-10", "0.717", "0.705", "0.721", "0.701", "100483532.000"], ["2026-11-11", "0.695", "0.723", "0.725", "0.693", "120440428.000"], ["2026-11-12", "0.721", "0.744", "0.770", "0.717", "110928839"]]}}}"#
            .utf8,
        )
        let candles = try ChartService.parseTencentCandles(candleData, code: "sh588170", period: .daily)
        let stock = Stock(id: "sh588170", name: "ETF", market: .aStock)
        let text = try AIAnalysisService.marketData(
            stock: stock,
            quote: nil,
            candles: candles,
            horizon: "短线",
            activity: snapshot,
        )
        let payload = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let bars = try #require(payload["dailyCandles"] as? [[String: Any]])
        #expect(bars.last?["volume"] as? Double == snapshot.volume)
        let metadata = try #require(payload["dailyCandleMetadata"] as? [String: Any])
        #expect(metadata["volumeUnit"] as? String == "份")
        let activity = try #require(payload["activity"] as? [String: Any])
        #expect(activity["amountCurrency"] as? String == "CNY")
        // 服务端缺少量比时省略，不补成零。
        var fields = response.components(separatedBy: "~")
        fields[49] = ""
        let missing = try #require(try AIAnalysisService.parseActivity(fields.joined(separator: "~"), code: "sh588170"))
        #expect(missing.payload["volumeRatio"] == nil)
    }
}
