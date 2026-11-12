import AppKit
import os
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        UNUserNotificationCenter.current().delegate = self
        appLogger.info("applicationDidFinishLaunching")
        logToFile("applicationDidFinishLaunching — pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void,
    ) {
        completionHandler([.banner, .list, .sound])
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
                .preferredColorScheme(appState.config.theme.preferredColorScheme)
        } label: {
            MenuBarLabel()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

        Window("Stockbar 设置", id: "settings") {
            SettingsView()
                .environmentObject(appState)
                .preferredColorScheme(appState.config.theme.preferredColorScheme)
        }
        .defaultSize(width: 820, height: 640)
        .windowResizability(.contentMinSize)

        Window("行情走势", id: "expanded-chart") {
            if let stock = appState.expandedChartStock {
                StockChartView(
                    stock: stock,
                    onClose: {},
                    isExpanded: true,
                    initialPeriod: appState.expandedChartPeriod,
                )
                    .id("\(stock.id)-\(appState.expandedChartPeriod.rawValue)")
                    .environmentObject(appState)
                    .preferredColorScheme(appState.config.theme.preferredColorScheme)
                    .padding(16)
                    .frame(minWidth: 640, minHeight: 400)
                    .background(ChartWindowFrameSaver())
            }
        }
        .defaultSize(width: 900, height: 540)
        .windowResizability(.contentMinSize)

        Window("AI 分析", id: "ai-analysis") {
            if let stock = appState.selectedAIStock {
                AIAnalysisView(stock: stock)
                    .id(stock.id)
                    .environmentObject(appState)
                    .preferredColorScheme(appState.config.theme.preferredColorScheme)
            }
        }
        .defaultSize(width: 620, height: 640)
        .windowResizability(.contentMinSize)

        Window("AI 历史报告", id: "ai-history") {
            AIReportHistoryView()
                .environmentObject(appState.aiReports)
                .preferredColorScheme(appState.config.theme.preferredColorScheme)
        }
        .defaultSize(width: 920, height: 640)
        .windowResizability(.contentMinSize)

        Window("AI 设置", id: "ai-settings") {
            AISettingsView().environmentObject(appState)
                .preferredColorScheme(appState.config.theme.preferredColorScheme)
        }
        .windowResizability(.contentSize)

        Window("价格提醒", id: "price-alerts") {
            if let stock = appState.selectedAlertStock {
                PriceAlertView(stock: stock)
                    .id(stock.id)
                    .environmentObject(appState)
                    .preferredColorScheme(appState.config.theme.preferredColorScheme)
                    .environmentObject(appState.priceAlerts)
            }
        }
        .defaultSize(width: 580, height: 420)
        .windowResizability(.contentMinSize)

        Window("新增股票", id: "add-stock") {
            ScrollView { AddStockView().padding(20) }
                .environmentObject(appState)
                .preferredColorScheme(appState.config.theme.preferredColorScheme)
                .frame(minWidth: 420, minHeight: 320)
        }
        .defaultSize(width: 460, height: 480)
        .windowResizability(.contentMinSize)

        Window("设置持仓", id: "holding-editor") {
            if let stock = appState.holdingEditorStock {
                HoldingEditorWindow(stock: stock)
                    .id(stock.id)
                    .environmentObject(appState)
                    .preferredColorScheme(appState.config.theme.preferredColorScheme)
            }
        }
        .windowResizability(.contentSize)
    }
}
