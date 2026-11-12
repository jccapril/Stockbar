import SwiftUI

struct MenuBarLabel: View {
    @EnvironmentObject var appState: AppState

    private var mode: String { appState.statusBarStockId }

    var body: some View {
        let isPnl = !appState.isStatusBarRotating &&
            (mode == "__daily_pnl__" || mode == "__total_pnl__" || mode == "__both_pnl__")

        HStack(spacing: 4) {
            if !isPnl {
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            }

            if isPnl {
                pnlText
            } else if let quote = appState.statusBarQuote {
                let title = switch appState.config.statusBarQuoteDisplay {
                case .price: quote.formattedPrice
                case .percent: quote.formattedPercent
                case .priceAndPercent: "\(quote.formattedPrice) \(quote.formattedPercent)"
                }
                // 合为一个标题，确保组合模式的两项行情都能显示。
                Text(appState.isStatusBarRotating ? "\(appState.statusBarStock?.name ?? "") \(title)" : title)
                    .font(.system(size: 12, weight: .medium))
            } else if appState.isStatusBarRotating, let stock = appState.statusBarStock {
                Text("\(stock.name) --")
                    .font(.system(size: 12))
            }

            if appState.hasError {
                Text("⚠").font(.system(size: 11))
            }
        }
    }

    /// 拼成一个 Text 显示，避免 @ViewBuilder 多分支问题
    private var pnlText: Text {
        guard appState.hasPnLData else {
            return Text("--").font(.system(size: 11))
        }
        let sym = appState.displayCurrency.symbol
        var parts: [Text] = []

        if mode == "__daily_pnl__" || mode == "__both_pnl__" {
            let d = appState.totalDailyPnL
            let s = "日\(d >= 0 ? "+" : "")\(sym)\(String(format: "%.0f", d))"
            parts.append(Text(s))
        }
        if mode == "__total_pnl__" || mode == "__both_pnl__" {
            let p = appState.totalPnL
            let s = "浮\(p >= 0 ? "+" : "")\(sym)\(String(format: "%.0f", p))"
            parts.append(Text(s))
        }

        let combined = parts.enumerated().reduce(Text("")) { result, item in
            item.offset == 0 ? item.element : result + Text(" ") + item.element
        }
        return combined.font(.system(size: 11, weight: .medium))
    }
}
