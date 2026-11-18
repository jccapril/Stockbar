// Created by april on 2026/11/12.
import SwiftUI

struct StockGroupsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var name = ""
    @State private var editingID: String?
    @State private var error = ""
    @State private var targetedGroupID: String?
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
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                        .draggable(group.id)
                        .help("拖动调整分组顺序")
                    Label(group.name, systemImage: "folder")
                    Text("\(appState.stocks.count(where: { $0.customGroupID == group.id })) 只")
                        .foregroundStyle(.secondary)
                    Spacer()
                    GroupOrderButtons(groupID: group.id).labelStyle(.iconOnly)
                    Button("重命名") { editingID = group.id; name = group.name; error = "" }
                    Button("删除", role: .destructive) { deleting = group }
                }
                .padding(.vertical, 3)
                .background(targetedGroupID == group.id ? Color.accentColor.opacity(0.12) : .clear)
                .dropDestination(for: String.self) { ids, _ in
                    guard let id = ids.first,
                          appState.config.customStockGroups.contains(where: { $0.id == id }) else { return false }
                    appState.moveStockGroup(id, to: group.id)
                    return true
                } isTargeted: { targeted in
                    if targeted { targetedGroupID = group.id }
                    else if targetedGroupID == group.id { targetedGroupID = nil }
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

struct GroupOrderButtons: View {
    let groupID: String
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let groups = appState.config.customStockGroups
        if let index = groups.firstIndex(where: { $0.id == groupID }) {
            ForEach([-1, 1], id: \.self) { offset in
                let destination = index + offset
                let title = offset < 0 ? "上移分组" : "下移分组"
                Button {
                    appState.moveStockGroup(groupID, to: groups[destination].id)
                } label: {
                    Label(title, systemImage: offset < 0 ? "arrow.up" : "arrow.down")
                }
                .disabled(!groups.indices.contains(destination))
                .help(title)
            }
        }
    }
}
