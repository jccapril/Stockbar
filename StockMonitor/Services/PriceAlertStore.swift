// Created by april on 2026/11/11.
import Combine
import Foundation
import UserNotifications

@MainActor
final class PriceAlertStore: ObservableObject {
    @Published private(set) var rules: [PriceAlert] = []
    @Published var errorMessage: String?
    private let fileURL: URL
    private var isEvaluating = false
    private var rapidTrackers: [UUID: RapidMoveTracker] = [:]

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("price-alerts.json")
        // 首次使用没有提醒文件；已有文件损坏时明确提示，不覆盖它。
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let loaded = try JSONDecoder().decode([PriceAlert].self, from: data)
            guard loaded.allSatisfy({
                $0.target.isFinite && ($0.metric == .percent || $0.target > 0)
                    && PriceAlert.validWindows.contains($0.windowMinutes)
                    && PriceAlert.validCooldowns.contains($0.cooldownMinutes)
            }) else {
                throw CocoaError(.coderReadCorrupt)
            }
            rules = loaded
        } catch {
            errorMessage = "读取价格提醒失败：\(error.localizedDescription)"
        }
    }

    func requestPermission() async -> Bool {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            errorMessage = allowed ? nil : "通知未获允许，请在系统设置 → 通知中允许本应用发送通知。"
            return allowed
        } catch {
            errorMessage = "申请通知权限失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func save(_ rule: PriceAlert) -> Bool {
        var updated = rules
        if let index = updated.firstIndex(where: { $0.id == rule.id }) {
            updated[index] = rule
        } else {
            updated.append(rule)
        }
        let saved = persist(updated)
        if saved { rapidTrackers.removeValue(forKey: rule.id) }
        return saved
    }

    func remove(_ id: UUID) {
        if persist(rules.filter { $0.id != id }) { rapidTrackers.removeValue(forKey: id) }
    }

    func removeStocks(_ ids: Set<String>) {
        // 删除自选时一并停止对应提醒，固定指数不受影响。
        let updated = rules.filter { !ids.contains($0.stockId) }
        if updated.count != rules.count { persist(updated) }
    }

    @discardableResult
    private func persist(_ updated: [PriceAlert]) -> Bool {
        do {
            let data = try JSONEncoder().encode(updated)
            try data.write(to: fileURL, options: .atomic)
            rules = updated
            errorMessage = nil
            return true
        } catch {
            errorMessage = "保存价格提醒失败：\(error.localizedDescription)"
            return false
        }
    }

    func evaluate(_ freshQuotes: [String: Quote]) async {
        // 定时刷新和手动刷新可能重叠，通知提交期间只运行一轮检查。
        guard !isEvaluating, rules.contains(where: \.isEnabled) else { return }
        isEvaluating = true
        defer { isEvaluating = false }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            errorMessage = "通知未获允许，提醒暂未发送。请在系统设置 → 通知中开启。"
            return
        }
        rapidTrackers = rapidTrackers.filter { id, _ in rules.contains { $0.id == id && $0.isEnabled } }
        for rule in rules where rule.isEnabled {
            // 只判断本轮实际返回的行情，不使用缓存中未刷新的报价。
            guard let quote = freshQuotes[rule.stockId], rules.contains(rule) else { continue }
            var rapidChange: Double?
            if rule.metric.isRapid {
                var tracker = rapidTrackers[rule.id] ?? RapidMoveTracker()
                rapidChange = tracker.observe(quote, at: Date(), rule: rule)
                rapidTrackers[rule.id] = tracker
                guard rapidChange != nil else { continue }
            } else if !rule.matches(quote) {
                continue
            }
            let content = UNMutableNotificationContent()
            content.title = "\(rule.stockName) · \(rule.metric.isRapid ? rule.metric.rawValue : "价格提醒")"
            content.body = "\(rule.summary)\n现价 \(quote.formattedPrice)，涨跌幅 \(quote.formattedPercent)\n\(rule.stockId) · \(quote.updateTime)"
            if let rapidChange {
                content.body = "近 \(rule.windowMinutes) 分钟变动 \(String(format: "%+.2f%%", rapidChange))\n现价 \(quote.formattedPrice)\n\(rule.stockId) · \(quote.updateTime)"
            }
            content.sound = .default
            let request = UNNotificationRequest(identifier: rule.id.uuidString, content: content, trigger: nil)
            do {
                try await center.add(request)
                // 普通提醒触发后停用，快速涨跌提醒保留启用并进入冷却。
                guard let index = rules.firstIndex(of: rule) else { continue }
                var updated = rules
                updated[index].isEnabled = rule.metric.isRapid
                updated[index].triggeredAt = Date()
                // 写盘失败仍在内存中保留触发时间／停用状态，避免每轮重复发送。
                if !persist(updated) { rules = updated }
            } catch {
                errorMessage = "发送提醒失败：\(error.localizedDescription)"
            }
        }
    }
}
