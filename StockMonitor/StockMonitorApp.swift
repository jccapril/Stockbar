import AppKit
import os
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        appLogger.info("applicationDidFinishLaunching")
        logToFile("applicationDidFinishLaunching — pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    func applicationWillTerminate(_: Notification) {
        appLogger.warning("applicationWillTerminate")
        logToFile("applicationWillTerminate")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        // 大图关闭后仍需驻留状态栏；退出由工具栏的退出按钮处理。
        false
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        appLogger.warning("applicationShouldTerminate called")
        logToFile("applicationShouldTerminate called")
        return .terminateNow
    }
}

@main
struct StockbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @State private var isStatusItemInserted = true

    var body: some Scene {
        MenuBarExtra(isInserted: $isStatusItemInserted) {
            DropdownView()
                .environmentObject(appState)
        } label: {
            MenuBarLabel()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

        Window("行情走势", id: "expanded-chart") {
            if let stock = appState.expandedChartStock {
                StockChartView(
                    stock: stock,
                    onClose: {},
                    isExpanded: true,
                    fiveDays: appState.expandedChartFiveDays,
                )
                    .id("\(stock.id)-\(appState.expandedChartFiveDays)")
                    .environmentObject(appState)
                    .padding(16)
                    .frame(minWidth: 640, minHeight: 400)
            }
        }
        .defaultSize(width: 900, height: 540)
        .windowResizability(.contentMinSize)
    }
}
