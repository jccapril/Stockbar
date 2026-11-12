import AppKit
import Combine
import CryptoKit
import Foundation

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlUrl: String
    let body: String?
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: String
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body
        case assets
    }
}

@MainActor
final class UpdateChecker: ObservableObject {

    static let shared = UpdateChecker()
    private init() {}
    private var automaticTask: Task<Void, Never>?
    private let skippedVersionKey = "skippedUpdateVersion"

    @Published var isBusy   = false
    @Published var status   = ""

    /// 入口：点击"检查更新"后调用
    func checkAndUpdate() {
        guard !isBusy else { return }
        isBusy  = true
        status  = "正在检查…"
        Task { await run() }
    }

    func configureAutomaticUpdates(enabled: Bool) {
        automaticTask?.cancel()
        automaticTask = nil
        // 开发版不参与正式版自动更新，避免覆盖开发环境。
        guard enabled, Bundle.main.bundleIdentifier == "com.vgearen.Stockbar" else { return }
        automaticTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if let self, !isBusy {
                    isBusy = true
                    status = "正在检查…"
                    await run(automatically: true)
                }
                do {
                    try await Task.sleep(nanoseconds: 6 * 60 * 60 * 1_000_000_000)
                } catch { return }
            }
        }
    }

    // MARK: - 主流程

    private func run(automatically: Bool = false) async {
        // 1. 获取最新 release
        guard let url = URL(string: "https://api.github.com/repos/jccapril/Stockbar/releases/latest")
            else { return finish("检查失败") }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let response = response as? HTTPURLResponse, response.statusCode == 200,
              let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            return finish("检查失败，请检查网络")
        }

        guard !Task.isCancelled else { return finish("") }
        let latestTag = release.tagName
        let latest  = latestTag.hasPrefix("v") ? String(latestTag.dropFirst()) : latestTag
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        guard isNewer(latest, than: current) else {
            return finish("已是最新版本")
        }

        // 跳过只影响后台提醒；手动检查仍可主动安装该版本。
        if automatically, UserDefaults.standard.string(forKey: skippedVersionKey) == latest {
            return finish("")
        }

        // 2. 找到 DMG 下载地址
        guard let dmgAsset = release.assets.first(where: { $0.name == "Stockbar-v\(latest).dmg" }),
              let downloadURL = URL(string: dmgAsset.browserDownloadUrl),
              downloadURL.scheme == "https", downloadURL.host == "github.com",
              downloadURL.path.hasPrefix("/jccapril/Stockbar/releases/download/\(latestTag)/") else {
            return finish("未找到安装包")
        }

        // 自动检查只负责提醒，下载和安装都必须由用户点击“更新”开始。
        switch confirmUpdate(latest: latest, current: current, notes: release.body) {
        case .alertFirstButtonReturn:
            UserDefaults.standard.removeObject(forKey: skippedVersionKey)
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(latest, forKey: skippedVersionKey)
            return finish("已跳过 v\(latest)")
        default:
            return finish("")
        }
        guard !Task.isCancelled else { return finish("") }

        // 4. 下载 + 安装
        isBusy = true
        status = "正在下载 v\(latest)…"
        await downloadAndInstall(url: downloadURL, version: latest, releaseBody: release.body)
    }

    // MARK: - 下载安装

    private func downloadAndInstall(url: URL, version: String, releaseBody: String?) async {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("StockbarUpdate-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch { return finish("无法创建更新目录") }

        // 下载 DMG
        let dmgPath = tempDir.appendingPathComponent("Stockbar.dmg")
        do {
            let (localURL, response) = try await URLSession.shared.download(from: url)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                return finish("下载安装包失败")
            }
            guard !Task.isCancelled else { return finish("") }
            try fm.moveItem(at: localURL, to: dmgPath)
        } catch {
            return finish("下载失败")
        }

        // SHA-256 校验
        guard let expectedHash = parseSHA256(from: releaseBody) else {
            return finish("发布信息缺少 SHA-256，无法验证安装包")
        }
        do {
            guard let dmgData = try? Data(contentsOf: dmgPath) else {
                return finish("校验失败")
            }
            let actualHash = SHA256.hash(data: dmgData).map { String(format: "%02x", $0) }.joined()
            guard actualHash.lowercased() == expectedHash.lowercased() else {
                logToFile("UpdateChecker: SHA-256 mismatch, expected=\(expectedHash) actual=\(actualHash)")
                return finish("校验失败")
            }
            logToFile("UpdateChecker: SHA-256 verified OK")
        }

        guard !Task.isCancelled else { return finish("") }
        status = "正在安装…"

        // 挂载 DMG
        let mountPoint = tempDir.appendingPathComponent("vol").path
        do {
            try fm.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)
        } catch { return finish("无法创建挂载目录") }
        guard shell("/usr/bin/hdiutil", "attach", dmgPath.path, "-mountpoint", mountPoint, "-nobrowse", "-quiet") == 0
            else {
            return finish("挂载失败")
        }

        // 找到 .app
        let sourceApp = "\(mountPoint)/Stockbar.app"
        guard let sourceBundle = Bundle(path: sourceApp),
              sourceBundle.bundleIdentifier == "com.vgearen.Stockbar",
              sourceBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version,
              let executable = sourceBundle.executableURL,
              fm.isExecutableFile(atPath: executable.path) else {
            shell("/usr/bin/hdiutil", "detach", mountPoint, "-quiet")
            return finish("安装包异常")
        }

        // 复制到临时目录
        let newApp = tempDir.appendingPathComponent("Stockbar.app").path
        do {
            try fm.copyItem(atPath: sourceApp, toPath: newApp)
        } catch {
            shell("/usr/bin/hdiutil", "detach", mountPoint, "-quiet")
            return finish("复制失败")
        }
        shell("/usr/bin/hdiutil", "detach", mountPoint, "-quiet")

        // 先复制到安装目录的相邻位置，复制失败时不退出、不改动正在运行的 App。
        let currentApp = Bundle.main.bundleURL
        guard fm.isWritableFile(atPath: currentApp.deletingLastPathComponent().path) else {
            return finish("应用目录不可写，请将安装包拖到应用程序目录安装")
        }
        let stagedApp = currentApp.deletingLastPathComponent()
            .appendingPathComponent(".Stockbar-new-\(UUID().uuidString).app")
        let backupApp = currentApp.deletingLastPathComponent()
            .appendingPathComponent(".Stockbar-backup-\(UUID().uuidString).app")
        let scriptPath = tempDir.appendingPathComponent("update.sh")
        do {
            try fm.copyItem(atPath: newApp, toPath: stagedApp.path)
            try Self.replacementScript.write(to: scriptPath, atomically: true, encoding: .utf8)
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [scriptPath.path, currentApp.path, stagedApp.path, backupApp.path,
                              tempDir.path, String(ProcessInfo.processInfo.processIdentifier)]
            try proc.run()
        } catch {
            logToFile("UpdateChecker: failed to prepare replacement: \(error)")
            return finish("准备更新失败，当前应用已保留")
        }
        status = "正在重启…"
        NSApplication.shared.terminate(nil)
    }

    // 同一目录内重命名；新版移入失败时恢复旧版，避免先删除导致应用丢失。
    static let replacementScript = """
    #!/bin/bash
    set -u
    while kill -0 "$5" 2>/dev/null; do sleep 0.2; done
    if ! /bin/mv "$1" "$3"; then
        /usr/bin/open "$1"
        exit 1
    fi
    if ! /bin/mv "$2" "$1"; then
        /bin/mv "$3" "$1"
        /usr/bin/open "$1"
        exit 1
    fi
    if ! /usr/bin/open "$1"; then
        /bin/mv "$1" "$2"
        /bin/mv "$3" "$1"
        /usr/bin/open "$1"
        exit 1
    fi
    /bin/rm -rf "$3" "$4"
    """

    /// 从 release body 中提取 SHA-256 哈希值（格式: SHA-256: <hex>）
    private func parseSHA256(from body: String?) -> String? {
        guard let body else { return nil }
        let pattern = #"SHA-256:\s*([0-9a-fA-F]{64})"#
        guard let range = body.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(body[range])
        // Extract just the hex part after "SHA-256:"
        let components = match.split(separator: ":", maxSplits: 1)
        guard components.count == 2 else { return nil }
        return components[1].trimmingCharacters(in: .whitespaces)
    }

    // MARK: - 确认弹窗

    private func confirmUpdate(latest: String, current: String, notes: String?) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = "发现新版本 v\(latest)"
        alert.informativeText = "当前版本 v\(current)。更新将下载、校验、安装并重启应用。"
        alert.addButton(withTitle: "更新")
        let cancel = alert.addButton(withTitle: "取消")
        cancel.keyEquivalent = "\u{1b}"
        alert.addButton(withTitle: "跳过此版本")

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 250))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.font = NSFont.systemFont(ofSize: 13)
        text.textColor = .labelColor
        text.textContainerInset = NSSize(width: 10, height: 10)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        let content = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        text.string = content.isEmpty ? "此版本未提供更新说明。" : content
        scroll.documentView = text
        alert.accessoryView = scroll
        // 菜单栏面板失焦会关闭，更新说明使用独立的前台模态窗口。
        NSApp.activate(ignoringOtherApps: true)
        alert.window.level = .floating
        alert.window.hidesOnDeactivate = false
        return alert.runModal()
    }

    // MARK: - 辅助

    private func finish(_ msg: String) {
        status = msg
        isBusy = false
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if status == msg { status = "" }
        }
    }

    @discardableResult
    private func shell(_ args: String...) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: args[0])
        proc.arguments = Array(args.dropFirst())
        do { try proc.run() }
        catch {
            logToFile("UpdateChecker: process failed: \(error)")
            return -1
        }
        proc.waitUntilExit()
        return proc.terminationStatus
    }

    /// 逐段比较语义版本
    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap  { Int($0) }
        let len = max(r.count, l.count)
        for i in 0..<len {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }
}
