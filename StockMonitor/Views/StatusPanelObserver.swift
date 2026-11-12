// Created by april on 2026/11/11.
import AppKit
import SwiftUI

/// MenuBarExtra 会复用内容视图，使用窗口焦点事件识别每次打开和关闭。
struct StatusPanelObserver: NSViewRepresentable {
    var theme: AppTheme
    var onFocusChange: (Bool) -> Void

    func makeNSView(context _: Context) -> ObserverView {
        let view = ObserverView()
        view.theme = theme
        view.onFocusChange = onFocusChange
        return view
    }

    func updateNSView(_ nsView: ObserverView, context _: Context) {
        nsView.onFocusChange = onFocusChange
        nsView.theme = theme
        nsView.applyTheme()
    }

    final class ObserverView: NSView {
        var onFocusChange: ((Bool) -> Void)?
        var theme: AppTheme = .system

        func applyTheme() {
            // MenuBarExtra 的 AppKit 面板不可靠地响应 preferredColorScheme，直接同步窗口外观。
            switch theme {
            case .system: window?.appearance = nil
            case .dark: window?.appearance = NSAppearance(named: .darkAqua)
            case .light: window?.appearance = NSAppearance(named: .aqua)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            applyTheme()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(didFocus),
                name: NSWindow.didBecomeKeyNotification,
                object: window,
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(didBlur),
                name: NSWindow.didResignKeyNotification,
                object: window,
            )
            // 首次挂载时窗口可能已成为主窗口，延后一轮避免在视图更新中修改状态。
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window?.isKeyWindow == true else { return }
                onFocusChange?(true)
            }
        }

        @objc
        private func didFocus() { onFocusChange?(true) }
        @objc
        private func didBlur() { onFocusChange?(false) }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
