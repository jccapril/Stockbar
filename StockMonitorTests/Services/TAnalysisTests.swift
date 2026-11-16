// Created by april on 2026/11/13.
import Foundation
import Testing
@testable import Stockbar

@MainActor
struct TAnalysisTests {
    @Test
    func automaticDecisionRequiresFreshTradingQuoteAndElapsedInterval() throws {
        let parser = ISO8601DateFormatter()
        let morning = try #require(parser.date(from: "2026-11-16T10:00:00+08:00"))
        let lunch = try #require(parser.date(from: "2026-11-16T11:30:00+08:00"))
        #expect(AppState.automaticTDue(
            now: morning,
            quoteTime: morning,
            lastStart: morning.addingTimeInterval(-300),
            minutes: 5,
        ))
        #expect(!AppState.automaticTDue(
            now: morning,
            quoteTime: morning,
            lastStart: morning.addingTimeInterval(-299),
            minutes: 5,
        ))
        #expect(!AppState.automaticTDue(
            now: lunch,
            quoteTime: lunch.addingTimeInterval(-1),
            lastStart: nil,
            minutes: 5,
        ))
        #expect(!AppState.automaticTDue(
            now: morning,
            quoteTime: morning.addingTimeInterval(-86400),
            lastStart: nil,
            minutes: 5,
        ))
    }

    @Test
    func decisionsEndpointAndChoices() throws {
        let url = try AIAnalysisService.endpoint("https://example.com/custom/v1/chat/completions")
        let request = try AIAnalysisService.tDecisionRequest(
            content: #"{"sampleCount":2}"#,
            chatURL: url,
            token: "test",
        )
        #expect(request.url?.absoluteString == "https://example.com/custom/v1/decisions")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["model"] as? String == "gpt-6-luna")
        for (choice, expected) in [("buy", AIAnalysisService.TDecision.Action.buy), ("sell", .sell), (
            "watch",
            .watch,
        )] {
            let response = try JSONSerialization.data(withJSONObject: ["answers": [["name": "intraday_action",
                                                                                    "type": "choice",
                                                                                    "choice": choice]]])
            #expect(try AIAnalysisService.decodeTChoice(response).action == expected)
        }
        let scored = try AIAnalysisService
            .decodeTChoice(
                Data(
                    #"{"answers":[{"name":"intraday_action","type":"choice","choice":"buy","confidence":0.9,"probabilities":[{"value":"sell","probability":0.2},{"value":"watch","probability":0.1},{"value":"buy","probability":0.7}]}]}"#
            .utf8,
                ),
            )
        #expect(scored.displayText == "买入\n模型概率  买入 70.0% · 卖出 20.0% · 观望 10.0%")
        #expect(throws: AIAnalysisService.Failure.self) {
            try AIAnalysisService
                .decodeTChoice(Data(#"{"answers":[{"name":"intraday_action","type":"refusal"}]}"#.utf8))
        }
    }

    @Test
    func partialWindowsAndHistoricalMarkers() throws {
        let stock = Stock(id: "sh510300", name: "ETF", market: .aStock)
        var quote = Array(repeating: "", count: 62)
        quote[4] = "4"
        quote[30] = "20261112094500"
        quote[61] = "ETF"
        let lines = (0..<16).map { minute in
            String(format: "%04d 4.1 %d %d", 930 + minute, 100 + minute * 10, 41000 + minute * 4100)
        }
        func snapshot(_ rows: [String], now: Date = Date()) throws -> AIAnalysisService.TSnapshot {
            let object: [String: Any] = ["data": [stock.id: ["data": ["date": "20261112", "data": rows],
                                                             "qt": [stock.id: quote]]]]
            return try AIAnalysisService.parseTSnapshot(
                JSONSerialization.data(withJSONObject: object),
                code: stock.id,
                now: now,
            )
        }
        for (count, expected) in [(1, [Int]()), (2, [1]), (4, [1, 3]), (6, [1, 3, 5]), (16, [1, 3, 5, 15])] {
            let sample = try snapshot(Array(lines.prefix(count)))
            let payload = try AIAnalysisService.tMarketData(stock: stock, snapshot: sample)
            let object = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
            #expect(object["availableWindowsMinutes"] as? [Int] == expected)
            #expect(sample.minutes.count == count)
            #expect(object["position"] == nil)
            #expect(object["dailyCandles"] == nil)
            #expect(object["simulationAssumptions"] as? String == AIAnalysisService.tAssumption)
        }
        let clock = try #require(ISO8601DateFormatter().date(from: "2026-11-12T09:31:51+08:00"))
        let completed = try snapshot(Array(lines.prefix(3)), now: clock)
        #expect(completed.latest.time == "0931")
        #expect(completed.minutes.count == 2)
        #expect(throws: AIAnalysisService.Failure.self) { try snapshot([lines[2]], now: clock) }
        let zero = try snapshot(["0930 4.1 0 0"])
        #expect(zero.averagePrice == nil)
        let gap = try snapshot([lines[0], lines[3]])
        #expect(!gap.hasRecentWindow)
        let gapJSON = try AIAnalysisService.tMarketData(stock: stock, snapshot: gap)
        let gapObject = try #require(JSONSerialization.jsonObject(with: Data(gapJSON.utf8)) as? [String: Any])
        #expect(gapObject["availableWindowsMinutes"] as? [Int] == [])

        let decision = AIAnalysisService.TDecision(action: .buy, entryCondition: "确认后")
        #expect(decision.action.marker == "B")
        #expect(AIAnalysisService.TDecision.Action.sell.marker == "S")
        let sample = try snapshot(lines)
        var analysis = AIAnalysisService.Analysis(
            text: "报告",
            lastTradingDay: sample.day,
            generatedAt: Date(),
            model: "test",
            horizon: AIAnalysisService.tHorizon,
            intradayAsOf: sample.latest.timestamp,
            intradayReferencePrice: 4.1,
            tDecision: decision,
        )
        let report = SavedAIReport(id: UUID(), stockID: stock.id, stockName: stock.name, analysis: analysis)
        let historical = AIAnalysisService.Analysis(
            text: "私人报告",
            lastTradingDay: sample.day,
            generatedAt: sample.latest.timestamp,
            model: "test",
            horizon: AIAnalysisService.tHorizon,
            intradayAsOf: sample.latest.timestamp,
            intradayReferencePrice: 4.1,
            intradaySummary: AIAnalysisService.tAssumption,
            tDecision: decision,
        )
        let same = SavedAIReport(id: UUID(), stockID: stock.id, stockName: stock.name, analysis: historical)
        let other = SavedAIReport(id: UUID(), stockID: "sh600000", stockName: "其他", analysis: historical)
        let prior = AIAnalysisService.priorTSignals([other, same], stockID: stock.id, asOf: sample.latest.timestamp)
        #expect(prior.count == 1)
        #expect(prior.first?["direction"] as? String == "B")
        #expect(prior.first?["entryCondition"] as? String == decision.entryCondition)
        #expect(AIAnalysisService.priorTSignals(
            [same],
            stockID: stock.id,
            asOf: sample.latest.timestamp.addingTimeInterval(86400),
        ).isEmpty)
        #expect(AIAnalysisService.priorTSignals(
            [same],
            stockID: stock.id,
            asOf: sample.latest.timestamp.addingTimeInterval(-60),
        ).isEmpty)
        let points = [MinutePoint(id: 2, time: "0945", price: 4.2, day: "20261111"),
                      MinutePoint(id: 5, time: "0945", price: 4.2, day: "20261112")]
        let markers = TAnalysisChartMarker.make(reports: [report], points: points)
        #expect(markers.count == 1)
        #expect(markers.first?.pointID == 5)
        #expect(markers.first?.price == 4.1)
        #expect(markers.first?.label == "B")
        analysis.tDecision = nil
        let old = SavedAIReport(id: UUID(), stockID: stock.id, stockName: stock.name, analysis: analysis)
        #expect(TAnalysisChartMarker.make(reports: [old], points: points).isEmpty)
        let roundTrip = try JSONDecoder().decode(SavedAIReport.self, from: JSONEncoder().encode(report))
        #expect(roundTrip.analysis.tDecision?.action == .buy)
    }
}
