import SwiftUI

@MainActor
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var updater = UpdateChecker.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var editingStock: Stock?
    @State private var selection: Category? = .general

    private enum Category: String, CaseIterable, Identifiable {
        case general = "通用"
        case statusBar = "状态栏"
        case list = "列表与排序"
        case stocks = "股票与持仓"
        case ai = "AI 分析"
        case about = "关于与更新"
        var id: Self { self }
        var icon: String {
            switch self {
            case .general: "gearshape"
            case .statusBar: "menubar.rectangle"
            case .list: "list.bullet"
            case .stocks: "chart.pie"
            case .ai: "sparkles"
            case .about: "info.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(Category.allCases, selection: $selection) { category in
                Label(category.rawValue, systemImage: category.icon)
                    .padding(.vertical, 6)
                    .tag(category)
            }
            .listStyle(.sidebar)
            .frame(width: 180)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text((selection ?? .general).rawValue)
                        .font(.title2.bold())
                    categoryContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 780, minHeight: 580)
        .onChange(of: selection) { _ in editingStock = nil }
    }

    @ViewBuilder
    private var categoryContent: some View {
        switch selection ?? .general {
        case .general:
            section("主题") {
                Picker("", selection: $appState.config.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }
            section("涨跌颜色") {
                HStack(spacing: 8) {
                    ForEach(ColorTheme.allCases, id: \.rawValue) { scheme in
                        colorCard(scheme)
                    }
                }
            }
            section("刷新间隔") {
                Picker("", selection: Binding(
                    get: { appState.refreshInterval },
                    set: { appState.refreshInterval = $0; appState.restartScheduler() },
                )) {
                    ForEach(AppSettings.validRefreshIntervals, id: \.self) { i in
                        Text("\(i) 秒").tag(i)
                    }
                }.pickerStyle(.segmented)
            }
            section("开机启动") {
                Toggle("登录后自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        LaunchAtLogin.setEnabled(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
            }
        case .statusBar:
            section("实时预览") {
                MenuBarLabel()
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    .frame(maxWidth: .infinity, minHeight: 48)
                Text("与当前状态栏同步，使用实际行情和持仓数据；开启轮播后会按设定间隔切换。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            section("状态栏显示") {
                Picker("", selection: Binding(
                    get: { appState.statusBarStockId },
                    set: { appState.statusBarStockId = $0 },
                )) {
                    Text("不显示").tag("__none__")
                    Text("日盈亏").tag("__daily_pnl__")
                    Text("总盈亏").tag("__total_pnl__")
                    Text("日盈亏 + 总盈亏").tag("__both_pnl__")
                    Divider()
                    Text("（自动选第一只）").tag("")
                    ForEach(appState.stocks) { s in
                        Text("\(s.name)  \(s.id)").tag(s.id)
                    }
                }.pickerStyle(.menu)
                .disabled(appState.config.statusBarRotationEnabled)
                Toggle("轮播置顶股票", isOn: $appState.config.statusBarRotationEnabled)
                if appState.config.statusBarRotationEnabled {
                    Picker("轮播间隔", selection: $appState.config.statusBarRotationInterval) {
                        ForEach(AppSettings.validRotationIntervals, id: \.self) { seconds in
                            Text("\(seconds) 秒").tag(seconds)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(appState.rotationStocks.isEmpty
                         ? "请先在列表中置顶股票。暂无置顶时沿用原显示方式。"
                         : "按置顶顺序轮播；点击查看当前股票走势，面板打开时暂停轮播。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            if appState.config.statusBarRotationEnabled || !appState.statusBarStockId.hasPrefix("__") {
                section("状态栏行情格式") {
                    Picker("", selection: Binding(
                        get: { appState.config.statusBarQuoteDisplay },
                        set: { appState.config.statusBarQuoteDisplay = $0 },
                    )) {
                        ForEach(StatusBarQuoteDisplay.allCases, id: \.rawValue) { format in
                            Text(format.displayName).tag(format)
                        }
                    }.pickerStyle(.menu)
                }
            }
        case .list:
            section("列表显示") {
                Toggle("显示列表搜索", isOn: $appState.config.showListSearch)
                Toggle("显示海外指数市场", isOn: $appState.config.showOverseasIndices)
            }
            section("持仓股展示") {
                Toggle("持仓股单独分组置顶", isOn: Binding(
                    get: { appState.config.groupHoldings },
                    set: { appState.config.groupHoldings = $0 },
                ))
                .padding(.leading, 8)
            }
            section("排序规则") {
                Picker("", selection: Binding(
                    get: { appState.config.sortRule },
                    set: { appState.config.sortRule = $0 },
                )) {
                    ForEach(SortRule.allCases, id: \.rawValue) { rule in
                        Text(rule.displayName).tag(rule)
                    }
                }.pickerStyle(.segmented)
            }
            section("美股排序价格") {
                Picker("", selection: Binding(
                    get: { appState.config.usPriceMode },
                    set: { appState.config.usPriceMode = $0 },
                )) {
                    ForEach(USPriceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }.pickerStyle(.segmented)
            }
        case .stocks:
            if let stock = editingStock {
                inlineEditView(stock)
            } else {
                section("持仓汇总货币") {
                    Picker("", selection: Binding(
                        get: { appState.displayCurrency },
                        set: { appState.displayCurrency = $0 },
                    )) {
                        ForEach(DisplayCurrency.allCases, id: \.rawValue) { c in
                            Text(c.displayName).tag(c)
                        }
                    }.pickerStyle(.segmented)
                }
                section("自定义分组") { StockGroupsSettingsView() }
                section("添加股票") { AddStockView() }
                if !appState.stocks.isEmpty {
                    section("我的股票") {
                        SettingsStockListView { editingStock = $0 }
                    }
                }
            }
        case .ai:
            section("AI 服务") { AISettingsView(isEmbedded: true) }
        case .about:
            section("更新") {
                Toggle("自动检查更新", isOn: $appState.config.automaticUpdatesEnabled)
                    .toggleStyle(.checkbox)
                Text("启动时及每隔 6 小时检查新版，显示更新内容，可选择更新、取消或跳过此版本。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if Bundle.main.bundleIdentifier != "com.vgearen.Stockbar" {
                    Text("开发版不自动检查正式版更新。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            section("关于") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stockbar")
                            .font(.system(size: 12, weight: .medium))
                        Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if updater.isBusy {
                        HStack(spacing: 4) {
                            ProgressView().scaleEffect(0.6)
                            Text(updater.status)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if !updater.status.isEmpty {
                        Text(updater.status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Button("检查更新") {
                            updater.checkAndUpdate()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - 子视图

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        } label: {
            Text(title).font(.headline)
        }
    }

    @ViewBuilder
    private func colorCard(_ scheme: ColorTheme) -> some View {
        let selected = appState.colorScheme == scheme
        Button { appState.colorScheme = scheme } label: {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text("涨").foregroundColor(scheme == .chinese ? .red : .green)
                    Text("跌").foregroundColor(scheme == .chinese ? .green : .red)
                }.font(.system(size: 12, weight: .medium))
                Text(scheme.displayName).font(.caption2).foregroundColor(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(selected ? Color.accentColor.opacity(0.15)
                                  : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
        }.buttonStyle(.plain)
    }

    private func inlineEditView(_ stock: Stock) -> some View {
        HoldingEditorView(
            stock: stock,
            onClose: { editingStock = nil },
        )
    }
}
