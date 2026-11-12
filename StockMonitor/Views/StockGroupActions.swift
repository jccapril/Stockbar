// Created by april on 2026/11/12.
import SwiftUI

struct StockGroupActions: View {
    let stock: Stock
    @EnvironmentObject var appState: AppState

    var body: some View {
        Button {
            appState.assignStock(stock.id, to: nil)
        } label: {
            Label("未分组（按市场显示）", systemImage: stock.customGroupID == nil ? "checkmark" : "folder")
        }
        ForEach(appState.config.customStockGroups) { group in
            Button {
                appState.assignStock(stock.id, to: group.id)
            } label: {
                Label(group.name, systemImage: stock.customGroupID == group.id ? "checkmark" : "folder")
            }
        }
    }
}
