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
}
