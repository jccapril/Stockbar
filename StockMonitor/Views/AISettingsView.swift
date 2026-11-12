// Created by april on 2026/11/11.
import SwiftUI

struct AISettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var address = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var message = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI 服务设置").font(.title2.bold())
            TextField("API 地址，例如 https://服务域名/v1", text: $address)
            Text("填写基础地址（含 /v1 等路径），也支持完整的 /chat/completions 地址。")
                .font(.caption).foregroundColor(.secondary)
            TextField("模型名称", text: $model)
            SecureField("API Key（留空保留该地址已保存的 Key）", text: $apiKey)
            Text("Key 保存在本机钥匙串。仅手动分析时向此服务发送股票代码、名称、公开报价及日 K，不发送持仓与成本。")
                .font(.callout).foregroundColor(.secondary)
            HStack {
                if !message.isEmpty {
                    Text(message).font(.caption).foregroundColor(saved ? .secondary : .red)
                }
                Spacer()
                Button("保存") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(24)
        .frame(width: 490)
        .onAppear {
            address = appState.config.aiAPIAddress
            model = appState.config.aiModel
        }
        .onChange(of: address) { _ in message = "" }
        .onChange(of: model) { _ in message = "" }
        .onChange(of: apiKey) { value in
            // 保存后清空输入框时保留成功提示。
            if !value.isEmpty { message = "" }
        }
    }

    private func save() {
        do {
            let endpoint = try AIAnalysisService.endpoint(address)
            let modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
            let newKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !modelName.isEmpty else { throw AIAnalysisService.Failure(message: "请填写模型名称。") }
            // 空白表示保留当前地址的 Key；换服务时不能沿用其他地址的凭据。
            if newKey.isEmpty {
                guard try !AIAnalysisService.key(for: endpoint).isEmpty else {
                    throw AIAnalysisService.Failure(message: "此地址还没有保存 API Key，请填写。")
                }
            } else {
                try AIAnalysisService.saveKey(newKey, for: endpoint)
            }
            appState.config.aiAPIAddress = endpoint.absoluteString
            appState.config.aiModel = modelName
            apiKey = ""
            saved = true
            message = "已保存"
        } catch {
            saved = false
            message = error.localizedDescription
        }
    }
}
