// Created by april on 2026/11/12.
import SwiftUI

struct StockGroupsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var name = ""
    @State private var editingID: String?
    @State private var error = ""
    @State private var deleting: CustomStockGroup?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField(editingID == nil ? "新分组名称，例如：长期关注" : "分组名称", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { save() }
                Button(editingID == nil ? "创建分组" : "保存") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if editingID != nil {
                    Button("取消") { editingID = nil; name = ""; error = "" }
                }
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            ForEach(appState.config.customStockGroups) { group in
                HStack {
                    Label(group.name, systemImage: "folder")
                    Text("\(appState.stocks.count(where: { $0.customGroupID == group.id })) 只")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("重命名") { editingID = group.id; name = group.name; error = "" }
                    Button("删除", role: .destructive) { deleting = group }
                }
            }
        }
        .alert("删除分组？", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } },
        )) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除分组", role: .destructive) {
                if let group = deleting {
                    appState.deleteStockGroup(group.id)
                    if editingID == group.id { editingID = nil; name = ""; error = "" }
                }
                deleting = nil
            }
        } message: {
            Text("删除“\(deleting?.name ?? "")”后，股票恢复原有分组显示，股票、持仓和置顶状态都会保留。")
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // 验证用户输入，避免空名称及与系统分组或其它自定义分组重名。
        guard !trimmed.isEmpty else { error = "请输入分组名称"; return }
        let reserved = ["置顶", "持仓", "未分组"] + Market.allCases.map(\.rawValue)
        guard !reserved.contains(trimmed), !appState.config.customStockGroups.contains(where: {
            $0.id != editingID && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) else { error = "这个名称已被使用，请换一个名称"; return }
        if let editingID {
            if let index = appState.config.customStockGroups.firstIndex(where: { $0.id == editingID }) {
                appState.config.customStockGroups[index].name = trimmed
            }
        } else {
            appState.config.customStockGroups.append(CustomStockGroup(name: trimmed))
        }
        editingID = nil
        name = ""
        error = ""
    }
}
