// Created by april on 2026/11/11.
import Charts
import SwiftUI

struct CandlestickChartView: View {
    let stock: Stock
    let period: CandlePeriod
    @EnvironmentObject var appState: AppState
    @State private var bars: [CandlePoint] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var visibleCount = 60
    @State private var endIndex = 0
    @State private var hoveredIndex: Int?
    @State private var dragStartEnd: Int?
    @State private var zoomStartCount: Int?

    private var visibleRange: Range<Int> {
        let end = min(max(endIndex, min(visibleCount, bars.count)), bars.count)
        return max(0, end - visibleCount)..<end
    }

    var body: some View {
        VStack(spacing: 4) {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loadFailed {
                Text("暂无 K 线数据").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                controls
                candleChart
                Text(
                    "\(bars[visibleRange.lowerBound].date) — \(bars[visibleRange.upperBound - 1].date) · \(stock.market == .usStock || stock.market == .krStock ? "拆股调整" : "不复权")",
                )
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .task(id: period) { await load() }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            RepeatingChartButton(
                symbol: "chevron.left",
                title: "向前移动，按住连续移动",
                isEnabled: visibleRange.lowerBound > 0,
            ) { move(by: -1) }
                .frame(width: 20, height: 20)
            Button { zoom(to: visibleCount * 2) } label: { Image(systemName: "minus") }
                .disabled(visibleCount >= bars.count)
                .help("缩小，显示更多 K 线")
            Button { zoom(to: visibleCount / 2) } label: { Image(systemName: "plus") }
                .disabled(visibleCount <= min(10, bars.count))
                .help("放大，显示更少 K 线")
            RepeatingChartButton(
                symbol: "chevron.right",
                title: "向后移动，按住连续移动",
                isEnabled: visibleRange.upperBound < bars.count,
            ) { move(by: 1) }
                .frame(width: 20, height: 20)
            Spacer(minLength: 0)
            Button("最新") { endIndex = bars.count; hoveredIndex = nil }
                .font(.system(size: 10))
                .disabled(visibleRange.upperBound == bars.count)
        }
        .buttonStyle(.plain)
    }

    private var candleChart: some View {
        let range = visibleRange
        let low = range.map { bars[$0].low }.min()!
        let high = range.map { bars[$0].high }.max()!
        let padding = max((high - low) * 0.08, high * 0.002)
        let ticks = Array(Set((0...3).map { range.lowerBound + (range.count - 1) * $0 / 3 })).sorted()
        return Chart {
            ForEach(range, id: \.self) { index in
                let bar = bars[index]
                let color = Color(bar.close >= bar.open ? appState.config.upColorName : appState.config.downColorName)
                RuleMark(x: .value("序号", index), yStart: .value("最低", bar.low), yEnd: .value("最高", bar.high))
                    .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1))
                if bar.open == bar.close {
                    RuleMark(
                        xStart: .value("左", Double(index) - 0.3),
                        xEnd: .value("右", Double(index) + 0.3),
                        y: .value("价格", bar.close),
                    )
                        .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1))
                } else {
                    RectangleMark(
                        xStart: .value("左", Double(index) - 0.3),
                        xEnd: .value("右", Double(index) + 0.3),
                        yStart: .value("实体低", min(bar.open, bar.close)),
                        yEnd: .value(
                            "实体高",
                            max(bar.open, bar.close),
                        ),
                    )
                        .foregroundStyle(color)
                }
            }
            if let index = hoveredIndex, range.contains(index) {
                RuleMark(x: .value("选中时间", index)).foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                RuleMark(y: .value("选中价格", bars[index].close)).foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            }
        }
        .chartXScale(domain: (Double(range.lowerBound) - 0.7)...(Double(range.upperBound) - 0.3))
        .chartYScale(domain: max(0, low - padding)...(high + padding))
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisValueLabel {
                    if let index = value.as(Int.self) {
                        Text(String(bars[index].date.dropFirst(2))).font(.system(size: 8))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel().font(.system(size: 8))
            }
        }
        .chartOverlay { proxy in interactionOverlay(proxy) }
    }

    private func interactionOverlay(_ proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            let plot = geometry[proxy.plotAreaFrame]
            ZStack(alignment: .topLeading) {
                Color.clear.contentShape(Rectangle())
                    .onContinuousHover { phase in
                        guard case let .active(location) = phase, plot.contains(location), dragStartEnd == nil,
                              let x: Double = proxy.value(atX: location.x - plot.minX) else {
                            hoveredIndex = nil
                            return
                        }
                        let index = Int(x.rounded())
                        hoveredIndex = visibleRange.contains(index) ? index : nil
                    }
                    .gesture(DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            // 从绘图区开始的拖动才移动历史区间，向右拖可查看更早行情。
                            guard plot.contains(value.startLocation) else { return }
                            if dragStartEnd == nil { dragStartEnd = visibleRange.upperBound }
                            hoveredIndex = nil
                            let offset = Int((value.translation.width / plot.width * Double(visibleRange.count))
                                .rounded())
                            endIndex = min(bars.count, max(min(visibleCount, bars.count), dragStartEnd! - offset))
                        }
                        .onEnded { _ in dragStartEnd = nil })
                    .simultaneousGesture(MagnificationGesture()
                        .onChanged { scale in
                            if zoomStartCount == nil { zoomStartCount = visibleCount }
                            zoom(to: Int((Double(zoomStartCount!) / scale).rounded()))
                        }
                        .onEnded { _ in zoomStartCount = nil })
                if let index = hoveredIndex, visibleRange.contains(index), let x = proxy.position(forX: index) {
                    details(bars[index])
                        .frame(width: 145, alignment: .leading)
                        .padding(6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                        .offset(x: x > plot.width / 2 ? plot.minX + 4 : plot.maxX - 161, y: plot.minY + 4)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func details(_ bar: CandlePoint) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(period == .weekly ? "周起始 \(bar.date)" : period == .monthly ? String(bar.date.prefix(7)) : bar.date)
            Text(String(format: "开 %.2f  收 %.2f", bar.open, bar.close))
            Text(String(format: "高 %.2f  低 %.2f", bar.high, bar.low))
            Text("涨跌幅 \(bar.changePercent.map { String(format: "%+.2f%%", $0) } ?? "—")")
            Text("相对上一根收盘价").foregroundStyle(.secondary)
        }
        .font(.system(size: 10)).monospacedDigit()
    }

    private func move(by offset: Int) {
        endIndex = min(bars.count, max(min(visibleCount, bars.count), visibleRange.upperBound + offset))
        hoveredIndex = nil
    }

    private func zoom(to count: Int) {
        visibleCount = min(bars.count, max(10, count))
        ChartPreferences.rememberVisibleCount(visibleCount, for: period)
        endIndex = max(endIndex, visibleCount)
        hoveredIndex = nil
    }

    private func load() async {
        isLoading = true
        visibleCount = ChartPreferences.visibleCount(for: period)
        loadFailed = false
        hoveredIndex = nil
        dragStartEnd = nil
        zoomStartCount = nil
        do {
            let result = try await ChartService.fetchCandles(stock: stock, period: period)
            try Task.checkCancellation()
            bars = result
            endIndex = result.count
        } catch {
            if Task.isCancelled { return }
            loadFailed = true
        }
        isLoading = false
    }
}
