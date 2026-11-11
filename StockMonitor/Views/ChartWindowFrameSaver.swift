// Created by april on 2026/11/11.
import AppKit
import SwiftUI

/// 由 AppKit 保存大图窗口的位置和尺寸，重开或重启后恢复。
struct ChartWindowFrameSaver: NSViewRepresentable {
    func makeNSView(context _: Context) -> FrameSaverView { FrameSaverView() }
    func updateNSView(_: FrameSaverView, context _: Context) {}

    final class FrameSaverView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let name = "Stockbar.ExpandedChart"
            // 切换股票会重建内容视图，同一个窗口只恢复一次，避免跳回旧位置。
            guard let window, window.frameAutosaveName != name else { return }
            window.setFrameUsingName(name)
            window.setFrameAutosaveName(name)
        }
    }
}
