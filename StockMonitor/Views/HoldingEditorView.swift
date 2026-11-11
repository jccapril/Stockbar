// Created by april on 2026/11/11.
import SwiftUI

struct HoldingEditorView: View {
    let stock: Stock
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
            HStack {
                Text("成本价")
                TextField("股票原币种，允许 0", text: $costText).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("持仓股数")
                TextField("大于 0，支持小数", text: $sharesText).textFieldStyle(.roundedBorder)
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
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
            let current = appState.stocks.first { $0.id == stock.id } ?? stock
            costText = current.costPrice.map { String($0) } ?? ""
            sharesText = current.holdingShares.map { String($0) } ?? ""
        }
    }

    private func save(_ values: (Double, Double)?) {
        // 独立窗口编辑期间，股票可能已从列表删除。
        guard let stockIndex = appState.stocks.firstIndex(where: { $0.id == stock.id }) else {
            errorMessage = "该股票已从列表删除。"
            return
        }
        var updated = appState.stocks
        updated[stockIndex].costPrice = values?.0
        updated[stockIndex].holdingShares = values?.1
        appState.stocks = updated
        onClose()
    }
}

struct HoldingEditorWindow: View {
    let stock: Stock
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HoldingEditorView(stock: stock, onClose: { dismiss() })
            .padding(20)
            .frame(width: 380)
    }
}
