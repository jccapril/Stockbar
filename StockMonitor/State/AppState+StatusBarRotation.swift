// Created by april on 2026/11/11.
import Foundation

extension AppState {
    var rotationStocks: [Stock] {
        let indices = Set(Self.marketIndices.map(\.id))
        return stocks.filter { $0.isPinned && !indices.contains($0.id) }
    }

    var isStatusBarRotating: Bool {
        config.statusBarRotationEnabled && !rotationStocks.isEmpty
    }

    func configureStatusBarRotation() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        let candidates = rotationStocks
        // 保留当前股票；取消置顶或删除后切换到新的第一只。
        if !candidates.contains(where: { $0.id == rotatingStockId }) {
            rotatingStockId = candidates.first?.id
        }
        guard config.statusBarRotationEnabled, candidates.count > 1 else { return }
        let timer = Timer(
            timeInterval: TimeInterval(config.statusBarRotationInterval),
            repeats: true,
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.advanceStatusBarRotation() }
        }
        RunLoop.main.add(timer, forMode: .common)
        rotationTimer = timer
    }

    func advanceStatusBarRotation() {
        // 面板打开时固定显示对象，避免用户查看的图表随定时器跳动。
        guard isStatusBarRotating, !isStatusPanelOpen else { return }
        let candidates = rotationStocks
        let current = candidates.firstIndex { $0.id == rotatingStockId } ?? -1
        rotatingStockId = candidates[(current + 1) % candidates.count].id
    }
}
