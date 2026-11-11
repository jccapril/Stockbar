// Created by april on 2026/11/11.
import SwiftUI

struct HoldingEditorView: View {
    let stock: Stock
    let watchlistId: String?
    let onClose: () -> Void
    @EnvironmentObject var appState: AppState
    @State private var costText = ""
    @State private var sharesText = ""
    @State private var errorMessage: String?

    private var values: (Double, Double)? {
        guard let cost = Double(costText.trimmingCharacters(in: .whitespaces)), cost.isFinite, cost >= 0,
              let shares = Double(sharesText.trimmingCharacters(in: .whitespaces)), shares.isFinite, shares > 0
        else { return nil }
        return (cost, shares)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设置持仓 · \(stock.name)").font(.headline)
            Text(watchlistId == nil ? "真实持仓" : appState.watchlists.first { $0.id == watchlistId }?.name ?? "观察仓已删除")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("成本价")
                TextField("股票原币种，允许 0", text: $costText).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("持仓股数")
                TextField("大于 0，支持小数", text: $sharesText).textFieldStyle(.roundedBorder)
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            if watchlistId != nil {
                Text("清除观察仓中的持仓后，将沿用该股票的真实持仓。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("清除持仓", role: .destructive) { save(nil) }
                Spacer()
                Button("取消", action: onClose)
                Button("保存") { save(values) }
                    .disabled(values == nil)
                    .buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            let entry = appState.watchlists.first { $0.id == watchlistId }?.entries[stock.id]
            let current = appState.stocks.first { $0.id == stock.id } ?? stock
            costText = (entry?.costPrice ?? current.costPrice).map { String($0) } ?? ""
            sharesText = (entry?.holdingShares ?? current.holdingShares).map { String($0) } ?? ""
        }
    }

    private func save(_ values: (Double, Double)?) {
        // 独立窗口编辑期间，股票或观察仓可能已被删除，不能写回到另一账户。
        guard let stockIndex = appState.stocks.firstIndex(where: { $0.id == stock.id }) else {
            errorMessage = "该股票已从列表删除。"
            return
        }
        if let watchlistId {
            guard let index = appState.watchlists.firstIndex(where: { $0.id == watchlistId }) else {
                errorMessage = "该观察仓已删除，请重新打开持仓编辑。"
                return
            }
            appState.watchlists[index].entries[stock.id] = values.map {
                WatchlistEntry(costPrice: $0.0, holdingShares: $0.1)
            }
        } else {
            var updated = appState.stocks
            updated[stockIndex].costPrice = values?.0
            updated[stockIndex].holdingShares = values?.1
            appState.stocks = updated
        }
        onClose()
    }
}

struct HoldingEditorWindow: View {
    let stock: Stock
    let watchlistId: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HoldingEditorView(stock: stock, watchlistId: watchlistId, onClose: { dismiss() })
            .padding(20)
            .frame(width: 380)
    }
}
