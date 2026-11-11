import SwiftUI

struct StockGroupView: View {
    let market: Market
    let stocks: [Stock]
    var title: String?
    var onSelect: ((Stock) -> Void)?
    var onDragChange: (Stock?, CGPoint?) -> Void
    var onDrop: (Stock, CGPoint) -> Void
    @EnvironmentObject var appState: AppState
    @State private var isExpanded = true
    @State private var draggingID: String?
    @State private var dragTranslation: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                    Text(title ?? market.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                    Text("(\(stocks.count))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)

            if isExpanded {
                ForEach(stocks) { stock in
                    StockRowView(
                        stock: stock,
                        quote: appState.quotes[stock.id],
                        onTap: { onSelect?(stock) },
                        onReorderDragChanged: { updateDrag(stock.id, value: $0) },
                        onReorderDragEnded: finishDrag,
                    )
                        .id(stock.id)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(
                                key: StockRowFramesKey.self,
                                value: [stock.id: geometry.frame(in: .named("stockList"))],
                            )
                        })
                        .offset(y: draggingID == stock.id ? dragTranslation : 0)
                        .zIndex(draggingID == stock.id ? 1 : 0)
                }
            }
        }
        .zIndex(draggingID == nil ? 0 : 1)
    }

    private func updateDrag(_ id: String, value: DragGesture.Value) {
        draggingID = id
        dragTranslation = value.translation.height
        // 由列表统一计算组内排序和跨组置顶的插入位置。
        onDragChange(stocks.first { $0.id == id }, value.location)
    }

    private func finishDrag(at location: CGPoint) {
        defer {
            draggingID = nil
            dragTranslation = 0
            onDragChange(nil, nil)
        }
        // 手势结束后只提交当前拖动的股票。
        guard let stock = stocks.first(where: { $0.id == draggingID }) else { return }
        onDrop(stock, location)
    }

}

struct StockRowFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
