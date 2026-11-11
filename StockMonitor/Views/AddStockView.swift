// Created by april on 2026/11/11.
import SwiftUI

struct AddStockView: View {
    @EnvironmentObject var appState: AppState
    @State private var query = ""
    @State private var results: [StockSearchService.SearchResult] = []
    @State private var isSearching = false
    @State private var searched = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("股票代码或名称", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { search() }
                    .disabled(isSearching)
                Button("搜索") { search() }
                    .disabled(isSearching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if isSearching { ProgressView().controlSize(.small) }
            }
            Text("支持 A 股、港股、美股和韩股；韩股可输入 005930.ks。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(results) { result in
                let added = appState.stocks.contains { $0.id == result.id }
                HStack {
                    VStack(alignment: .leading) {
                        Text(result.name)
                        Text("\(result.id) · \(result.market.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(added ? "已添加" : "添加") {
                        appState.stocks.append(Stock(id: result.id, name: result.name, market: result.market))
                        appState.forceRefresh()
                    }
                    .disabled(added)
                }
                Divider()
            }
            if searched, !isSearching, results.isEmpty {
                Text("未找到结果，请检查代码或网络后重试。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func search() {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, !isSearching else { return }
        isSearching = true
        searched = true
        results = []
        Task {
            results = await StockSearchService.fetchSuggestions(keyword)
            isSearching = false
        }
    }
}
