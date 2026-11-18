// Created by april on 2026/11/11.
import AppKit
import SwiftUI

/// 由 AppKit 保存大图窗口的位置和尺寸，重开或重启后恢复。
struct ChartWindowFrameSaver: NSViewRepresentable {
    var name = "Stockbar.ExpandedChart"

    func makeNSView(context _: Context) -> FrameSaverView {
        let view = FrameSaverView()
        view.autosaveKey = name
        return view
    }

    func updateNSView(_: FrameSaverView, context _: Context) {}

    final class FrameSaverView: NSView {
        var autosaveKey = ""

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let name = autosaveKey
            // 切换股票会重建内容视图，同一个窗口只恢复一次，避免跳回旧位置。
            guard let window, window.frameAutosaveName != name else { return }
            window.setFrameUsingName(name)
            window.setFrameAutosaveName(name)
        }
    }
}
