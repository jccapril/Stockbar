import Foundation

@MainActor
final class RefreshScheduler {
    private var timer: Timer?
    private var pendingTask: Task<Void, Never>?
    private let onRefresh: () async -> Void

    init(onRefresh: @escaping () async -> Void) {
        self.onRefresh = onRefresh
    }

    /// 启动定时刷新（立即触发一次）
    func start(interval: TimeInterval) {
        stop()
        pendingTask = Task { await onRefresh() }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                // 休市后保留两分钟收尾窗口，获取接口延迟返回的最后一笔行情。
                guard let self, Self.shouldAutoRefresh() else { return }
                pendingTask = Task { await self.onRefresh() }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pendingTask?.cancel()
        pendingTask = nil
    }

    /// 强制刷新（忽略开市判断）
    func forceRefresh() {
        pendingTask = Task { await onRefresh() }
    }

    // MARK: - 开市时段判断（北京时间）

    private nonisolated static let shanghaiCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    /// 交易期间刷新，午休和收盘后再延续两分钟；随后停止自动请求。
    nonisolated static func shouldAutoRefresh(at date: Date = Date()) -> Bool {
        isTradingHour(at: date) || isTradingHour(at: date.addingTimeInterval(-120))
    }

    /// A 股常规交易时段，不包含休市后的收尾刷新窗口。
    /// 注：不维护节假日日历，节假日由接口返回不变的数据来体现
    nonisolated static func isTradingHour(at date: Date = Date()) -> Bool {
        let cal = shanghaiCalendar

        let weekday = cal.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 { return false }   // 周日=1, 周六=7

        let hour   = cal.component(.hour,   from: date)
        let minute = cal.component(.minute, from: date)
        let t = hour * 60 + minute

        return (9 * 60 + 30..<11 * 60 + 30).contains(t)
            || (13 * 60..<15 * 60).contains(t)
    }
}
