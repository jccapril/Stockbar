// Created by april on 2026/11/11.
import AppKit
import SwiftUI

/// 使用原生按钮的连续追踪，按下即移动，长按重复，松开自动停止。
struct RepeatingChartButton: NSViewRepresentable {
    let symbol: String
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
        button.isContinuous = true
        button.setPeriodicDelay(0.35, interval: 0.08)
        button.sendAction(on: [.leftMouseDown, .periodic])
        button.isEnabled = isEnabled
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = isEnabled
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) { self.action = action }

        @objc
        func performAction() { action() }
    }
}
