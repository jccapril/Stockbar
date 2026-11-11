import Charts
import SwiftUI

struct StockChartView: View {
    let stock: Stock
    let onClose: () -> Void
    let isExpanded: Bool
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    @State private var points: [MinutePoint] = []
    @State private var preClose: Double = 0
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var period: Period = .intraday
    @State private var hoveredPoint: MinutePoint?

    private enum Period: String, CaseIterable {
        case intraday = "分时"
        case fiveDays = "五日"
    }

    init(stock: Stock, onClose: @escaping () -> Void, isExpanded: Bool = false, fiveDays: Bool = false) {
        self.stock = stock
        self.onClose = onClose
        self.isExpanded = isExpanded
        _period = State(initialValue: fiveDays ? .fiveDays : .intraday)
    }

    private var quote: Quote? { appState.quotes[stock.id] }

    // MARK: - 全天 x 轴范围（按市场）
    // A股：09:30-11:30 + 13:00-15:00 = 240 分钟
    // 港股：09:30-12:00 + 13:00-16:00 = 330 分钟
    // 美股：04:00-20:00 = 960 分钟（含盘前+正常+盘后）
    private var fullDayRange: ClosedRange<Int> {
        // 五日数据已按交易日连接，跳过周末和夜间空档。
        if period == .fiveDays { return 0...max(points.last?.id ?? 0, 1) }
        switch stock.market {
        case .aStock:  return 0...239
        case .hkStock: return 0...329
        case .usStock: return 0...959
        case .krStock: return 0...389
        }
    }

    // 对应各市场的时间标签（index → 时间字符串）
    private var xAxisLabels: [(Int, String)] {
        if period == .fiveDays {
            let days = Dictionary(grouping: points, by: \.day)
            return days.keys.sorted().compactMap { day in
                guard let items = days[day], let first = items.first, let last = items.last else { return nil }
                let monthDay = day.suffix(4)
                return ((first.id + last.id) / 2, "\(monthDay.prefix(2))/\(monthDay.suffix(2))")
            }
        }
        switch stock.market {
        case .aStock:
            return [(0, "09:30"), (60, "10:30"), (120, "13:00"), (180, "14:00"), (239, "15:00")]
        case .hkStock:
            return [(0, "09:30"), (75, "10:45"), (150, "13:00"), (240, "15:00"), (329, "16:00")]
        case .usStock:
            // 基准 04:00 ET；330=09:30；720=16:00；959=19:59
            return [(0, "04:00"), (330, "09:30"), (570, "13:30"), (720, "16:00"), (959, "20:00")]
        case .krStock:
            // 基准 09:00 KST；180=12:00；389=15:29
            return [(0, "09:00"), (90, "10:30"), (180, "12:00"), (270, "13:30"), (389, "15:30")]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Picker("走势图周期", selection: $period) {
                ForEach(Period.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
            Divider()
            chartAreaView
                .frame(minHeight: isExpanded ? 280 : 200, maxHeight: isExpanded ? .infinity : 200)
            if !isLoading, !loadFailed, !points.isEmpty {
                statsRow
            }
        }
        .task(id: period) { await load() }
    }

    // MARK: - 顶部信息栏

    private var headerView: some View {
        HStack(alignment: .center, spacing: 6) {
            if !isExpanded {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(stock.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(stock.id)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                appState.selectedAlertStock = stock
                openWindow(id: "price-alerts")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "bell")
            }
            .buttonStyle(.plain)
            .help("价格提醒")
            .accessibilityLabel("价格提醒")

            if !isExpanded {
                Button {
                    appState.expandedChartStock = stock
                    appState.expandedChartFiveDays = period == .fiveDays
                    openWindow(id: "expanded-chart")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.plain)
                .help("展开图表")
                .accessibilityLabel("展开图表")
            }

            if let q = quote {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(q.formattedPrice)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(appState.quoteColor(for: q))
                    Text(q.formattedPercent)
                        .font(.system(size: 10))
                        .foregroundColor(appState.quoteColor(for: q))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - 图表区域

    @ViewBuilder
    private var chartAreaView: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if loadFailed || points.isEmpty {
            Text(period == .fiveDays ? "暂无五日数据" : "暂无分时数据")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            lineChart
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }

    // 美股时段定义：x 轴 index（基准 04:00 ET，每分钟 +1）
    private let usSessions: [(name: String, start: Int, end: Int, color: Color)] = [
        ("盘前", 0,   329, Color.indigo),
        ("盘中", 330, 719, Color.teal),
        ("盘后", 720, 959, Color.orange),
    ]

    private var lineChart: some View {
        let prices = points.map(\.price)
        let minP = prices.min() ?? preClose
        let maxP = prices.max() ?? preClose
        let maxDev = max(abs(maxP - preClose), abs(preClose - minP), preClose * 0.005)
        let yMin = preClose - maxDev * 1.15
        let yMax = preClose + maxDev * 1.15

        let lastPrice = prices.last ?? preClose
        let lineColor: Color = lastPrice >= preClose
            ? Color(appState.config.upColorName)
            : Color(appState.config.downColorName)

        let labelPositions = xAxisLabels.map(\.0)
        let isUS = stock.market == .usStock && period == .intraday
        let labelY = yMin + (yMax - yMin) * 0.88
        let dayBoundaries = zip(points, points.dropFirst()).compactMap { previous, next in
            previous.day != next.day ? (Double(previous.id) + Double(next.id)) / 2 : nil
        }

        return Chart {
            // 美股时段背景色块
            if isUS {
                ForEach(usSessions, id: \.name) { s in
                    RectangleMark(
                        xStart: .value("xs", s.start),
                        xEnd:   .value("xe", s.end),
                        yStart: .value("ys", yMin),
                        yEnd:   .value("ye", yMax),
                    )
                    .foregroundStyle(s.color.opacity(0.07))
                }
                // 美股时段文字标注
                ForEach(usSessions, id: \.name) { s in
                    PointMark(
                        x: .value("t", (s.start + s.end) / 2),
                        y: .value("price", labelY),
                    )
                    .symbolSize(0)
                    .annotation(position: .overlay) {
                        Text(s.name)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(s.color.opacity(0.65))
                    }
                }
            }

            // 昨收参考线
            RuleMark(y: .value("昨收", preClose))
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                .foregroundStyle(Color.secondary.opacity(0.5))

            // 价格折线
            ForEach(points) { p in
                LineMark(
                    x: .value("t", p.id),
                    y: .value("price", p.price),
                    series: .value("交易日", p.day),
                )
                .interpolationMethod(.linear)
                .foregroundStyle(lineColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }

            // 面积填充
            ForEach(points) { p in
                AreaMark(
                    x: .value("t", p.id),
                    yStart: .value("base", yMin),
                    yEnd: .value("price", p.price),
                    series: .value("交易日", p.day),
                )
                .foregroundStyle(lineColor.opacity(0.04))
            }

            if period == .fiveDays {
                ForEach(dayBoundaries, id: \.self) { boundary in
                    RuleMark(x: .value("交易日分界", boundary))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                }
            }
            if let point = hoveredPoint {
                RuleMark(x: .value("时间", point.id))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                RuleMark(y: .value("选中价格", point.price))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                PointMark(x: .value("t", point.id), y: .value("price", point.price))
                    .foregroundStyle(lineColor)
                    .symbolSize(35)
            }
        }
        .chartXScale(domain: fullDayRange)
        .chartYScale(domain: yMin...yMax)
        .chartXAxis {
            AxisMarks(values: labelPositions) { value in
                if period == .intraday {
                    AxisGridLine()
                        .foregroundStyle(Color.secondary.opacity(0.2))
                }
                AxisValueLabel {
                    if let i = value.as(Int.self),
                       let label = xAxisLabels.first(where: { $0.0 == i })?.1 {
                        Text(label)
                            .font(.system(size: 8))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel()
                    .font(.system(size: 8))
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartOverlay { proxy in
            hoverOverlay(proxy: proxy)
        }
        .onChange(of: period) { _ in hoveredPoint = nil }
    }

    private func hoverOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            let plot = geometry[proxy.plotAreaFrame]
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            // 坐标轴和未交易的空白区域不显示历史采样，避免误认时间。
                            guard plot.contains(location),
                                  let x: Double = proxy.value(atX: location.x - plot.minX),
                                  let first = points.first, let last = points.last,
                                  x >= Double(first.id) - 0.5, x <= Double(last.id) + 0.5 else {
                                hoveredPoint = nil
                                return
                            }
                            hoveredPoint = points.min { abs(Double($0.id) - x) < abs(Double($1.id) - x) }
                        case .ended:
                            hoveredPoint = nil
                        }
                    }
                if let point = hoveredPoint, let x = proxy.position(forX: point.id) {
                    hoverDetails(point)
                        .frame(width: 145, alignment: .leading)
                        .padding(6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                        .offset(
                            x: x > plot.width / 2 ? plot.minX + 4 : plot.maxX - 161,
                            y: plot.minY + 4,
                        )
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func hoverDetails(_ point: MinutePoint) -> some View {
        let time = point.time.contains(":") ? point.time : "\(point.time.prefix(2)):\(point.time.suffix(2))"
        let date = "\(point.day.prefix(4))/\(point.day.dropFirst(4).prefix(2))/\(point.day.suffix(2))"
        let change = preClose > 0 ? (point.price / preClose - 1) * 100 : nil
        return VStack(alignment: .leading, spacing: 3) {
            Text(period == .fiveDays ? "\(date) \(time)" : time)
            Text("价格  \(String(format: point.price >= 10 ? "%.2f" : "%.3f", point.price))")
            Text("涨跌幅  \(change.map { String(format: "%+.2f%%", $0) } ?? "—")")
                .foregroundStyle(Color(point.price >= preClose ? appState.config.upColorName : appState.config
                    .downColorName))
            Text(period == .fiveDays ? "相对五日起始前收盘价" : "相对昨收")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 10))
        .monospacedDigit()
    }

    // MARK: - 底部统计
    // 今开：分时第一个点的价格；昨收：API 返回的 preclose

    private var statsRow: some View {
        let prices = points.map(\.price)
        return HStack(spacing: 0) {
            statItem(label: period == .fiveDays ? "基准" : "昨收", value: fmt(preClose))
            Spacer()
            statItem(label: period == .fiveDays ? "首价" : "今开", value: fmt(points.first?.price ?? 0))
            Spacer()
            statItem(label: "最高", value: fmt(prices.max() ?? 0))
            Spacer()
            statItem(label: "最低", value: fmt(prices.min() ?? 0))
            Spacer()
            statItem(
                label: period == .fiveDays ? "末价" : "现价",
                value: fmt(period == .fiveDays ? points.last?.price ?? 0 : quote?.price ?? 0),
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 9)).foregroundColor(.secondary)
            Text(value).font(.system(size: 10, weight: .medium))
        }
    }

    private func fmt(_ v: Double) -> String {
        // 韩元等大数字（如 284000）用整数显示；港币/美元中等数字 2 位小数；小数价 3 位
        if v >= 1000 { return String(format: "%.0f", v) }
        if v >= 10   { return String(format: "%.2f", v) }
        return String(format: "%.3f", v)
    }

    // MARK: - 数据加载

    private func load() async {
        isLoading = true
        loadFailed = false
        points = []
        hoveredPoint = nil
        do {
            let (pts, pc) = try await (period == .fiveDays
                ? ChartService.fetchFiveDay(stock: stock)
                : ChartService.fetchIntraday(stock: stock))
            // 切换周期会取消旧任务，旧响应不得覆盖新周期的状态。
            try Task.checkCancellation()
            points = pts
            preClose = pc > 0 ? pc : (quote?.previousClose ?? 0)
        } catch {
            if Task.isCancelled { return }
            loadFailed = true
        }
        isLoading = false
    }
}
