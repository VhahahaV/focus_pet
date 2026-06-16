import AppKit
import Foundation

enum InstallationNoticeCoordinator {
    private static let lastShownBuildKey = "FocusPetLastInstallNoticeBuild"

    static func showLaunchNoticeIfNeeded() {
        let bundleURL = Bundle.main.bundleURL

        if isRunningFromMountedVolume(bundleURL) {
            showNotice(
                title: "请先完成安装",
                message: "请将 Focus Pet 拖到 Applications 文件夹后再打开。直接从 DMG 运行可能无法稳定保存权限和用户数据。"
            )
            return
        }

        guard isInstalledApplication(bundleURL) else { return }

        let buildIdentifier = currentBuildIdentifier
        let previousBuildIdentifier = UserDefaults.standard.string(forKey: lastShownBuildKey)
        guard previousBuildIdentifier != buildIdentifier else { return }

        let title = previousBuildIdentifier == nil ? "Focus Pet 已安装完成" : "Focus Pet 已更新完成"
        showNotice(
            title: title,
            message: "当前版本 \(versionDisplay) 已就绪。你的原有数据会继续保存在 ~/Library/Application Support/Focus Pet。",
            shownBuildIdentifier: buildIdentifier
        )
    }

    private static func showNotice(title: String, message: String, shownBuildIdentifier: String? = nil) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            NSApp.activate(ignoringOtherApps: true)
            NSRunningApplication.current.activate(options: [.activateAllWindows])

            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "知道了")
            alert.window.level = .floating
            alert.runModal()
            if let shownBuildIdentifier {
                UserDefaults.standard.set(shownBuildIdentifier, forKey: lastShownBuildKey)
            }
        }
    }

    private static var currentBuildIdentifier: String {
        "\(bundleInfoValue("CFBundleShortVersionString"))|\(bundleInfoValue("CFBundleVersion"))"
    }

    private static var versionDisplay: String {
        let version = bundleInfoValue("CFBundleShortVersionString")
        let build = bundleInfoValue("CFBundleVersion")
        guard version != build else { return version }
        return "\(version) (\(build))"
    }

    private static func bundleInfoValue(_ key: String) -> String {
        Bundle.main.infoDictionary?[key] as? String ?? "Unknown"
    }

    private static func isRunningFromMountedVolume(_ bundleURL: URL) -> Bool {
        bundleURL.path.hasPrefix("/Volumes/")
    }

    private static func isInstalledApplication(_ bundleURL: URL) -> Bool {
        let path = bundleURL.path
        let userApplicationsPath = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Applications", isDirectory: true)
            .path

        return path.hasPrefix("/Applications/")
            || path.hasPrefix("\(userApplicationsPath)/")
    }
}
