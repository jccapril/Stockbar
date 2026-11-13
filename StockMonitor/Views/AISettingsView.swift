// Created by april on 2026/11/11.
import SwiftUI

struct AISettingsView: View {
    var isEmbedded = false
    @EnvironmentObject var appState: AppState
    @State private var address = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var models: [String] = []
    @State private var message = ""
    @State private var succeeded = false
    @State private var operation: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !isEmbedded { Text("AI 服务设置").font(.title2.bold()) }
            TextField("API 地址，例如 https://服务域名/v1", text: Binding(
                get: { address },
                set: { value in
                    // TextField 同步相同文本时也可能写回绑定，不能因此清空已读取的 Key。
                    guard value != address else { return }
                    address = value
                    apiKey = ""
                    models = []
                    message = ""
                },
            ))
            .onSubmit { loadKey() }
            Text("填写基础地址（含 /v1 等路径），也支持完整的 /chat/completions 地址。")
                .font(.caption).foregroundColor(.secondary)
            HStack {
                AIModelComboBox(selection: $model, models: models)
                    .frame(height: 24)
                Button("获取模型") { perform(test: false) }
            }
            SecureField("API Key（密码模式）", text: $apiKey)
            HStack {
                if operation != nil { ProgressView().controlSize(.small) }
                if !message.isEmpty {
                    Text(message).font(.caption).foregroundColor(succeeded ? .secondary : .red)
                }
                Spacer()
                Button("测试连接") { perform(test: true) }
                Button("保存") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .disabled(operation != nil)
        .textFieldStyle(.roundedBorder)
        .padding(isEmbedded ? 0 : 24)
        .frame(width: isEmbedded ? nil : 530)
        .onAppear {
            address = appState.config.aiAPIAddress
            model = appState.config.aiModel
            loadKey()
        }
        .onChange(of: model) { _ in message = "" }
        .onChange(of: apiKey) { _ in message = "" }
        .onDisappear { operation?.cancel() }
    }

    private func loadKey() {
        do {
            apiKey = try AIAnalysisService.key(for: AIAnalysisService.endpoint(address))
        } catch {
            succeeded = false
            message = error.localizedDescription
        }
    }

    private func perform(test: Bool) {
        message = ""
        let token = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !test || !selectedModel.isEmpty else {
            succeeded = false
            message = test ? "请填写 API Key 和模型名称。" : "请先填写 API Key。"
            return
        }
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                if test {
                    try await AIAnalysisService.testConnection(address: address, model: selectedModel, token: token)
                    message = "连接成功，模型可用"
                } else {
                    models = try await AIAnalysisService.fetchModels(address: address, token: token)
                    message = models.isEmpty ? "服务没有返回模型，可手动输入。" : "已获取 \(models.count) 个模型，请从下拉框选择。"
                }
                succeeded = true
            } catch {
                if !Task.isCancelled {
                    succeeded = false
                    message = error is DecodingError ? "接口返回格式不兼容，请检查 API 地址。" : error.localizedDescription
                }
            }
        }
    }

    private func save() {
        do {
            let endpoint = try AIAnalysisService.endpoint(address)
            let modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
            let newKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !modelName.isEmpty else { throw AIAnalysisService.Failure(message: "请填写模型名称。") }
            if !newKey.isEmpty {
                try AIAnalysisService.saveKey(newKey, for: endpoint)
            }
            appState.config.aiAPIAddress = endpoint.absoluteString
            appState.config.aiModel = modelName
            succeeded = true
            message = "已保存"
        } catch {
            succeeded = false
            message = error.localizedDescription
        }
    }
}
