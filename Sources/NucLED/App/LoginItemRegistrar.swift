import Foundation
import ServiceManagement

/// Registers or unregisters the main app as a login item on the user's request.
@MainActor
struct LoginItemRegistrar {
    struct UpdateResult {
        /// Whether macOS currently has the app registered or awaiting approval.
        let isEnabled: Bool
        let statusText: String?
    }

    var isEnabledOrPendingApproval: Bool {
        guard #available(macOS 13.0, *) else {
            return false
        }
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) -> UpdateResult {
        guard #available(macOS 13.0, *) else {
            return UpdateResult(
                isEnabled: false,
                statusText: enabled ? "登录启动需要 macOS 13 或更高版本" : nil
            )
        }

        return enabled ? register() : unregister()
    }

    @available(macOS 13.0, *)
    private func register() -> UpdateResult {
        let service = SMAppService.mainApp
        switch service.status {
        case .enabled:
            return UpdateResult(isEnabled: true, statusText: nil)
        case .requiresApproval:
            return UpdateResult(isEnabled: true, statusText: approvalInstructions)
        case .notRegistered, .notFound:
            let bundleURL = Bundle.main.bundleURL
            let installedBundlePath = bundleURL.resolvingSymlinksInPath().path
            let applicationsPath = URL(fileURLWithPath: "/Applications", isDirectory: true).path + "/"
            guard bundleURL.pathExtension.lowercased() == "app",
                  Bundle.main.bundleIdentifier != nil,
                  installedBundlePath.hasPrefix(applicationsPath) else {
                return UpdateResult(
                    isEnabled: false,
                    statusText: "请先将 NucLED.app 安装到“应用程序”文件夹，再启用登录启动。"
                )
            }

            do {
                try service.register()
            } catch {
                if service.status == .requiresApproval {
                    return UpdateResult(isEnabled: true, statusText: approvalInstructions)
                }
                return UpdateResult(
                    isEnabled: false,
                    statusText: "无法启用登录启动：\(error.localizedDescription)"
                )
            }

            if service.status == .requiresApproval {
                return UpdateResult(isEnabled: true, statusText: approvalInstructions)
            }
            return service.status == .enabled
                ? UpdateResult(isEnabled: true, statusText: nil)
                : UpdateResult(
                    isEnabled: true,
                    statusText: "已请求登录启动；请在系统设置“通用 › 登录项”确认状态。"
                )
        @unknown default:
            return UpdateResult(
                isEnabled: false,
                statusText: "无法确认登录启动状态；请检查系统设置“通用 › 登录项”。"
            )
        }
    }

    @available(macOS 13.0, *)
    private func unregister() -> UpdateResult {
        let service = SMAppService.mainApp
        switch service.status {
        case .notRegistered, .notFound:
            return UpdateResult(isEnabled: false, statusText: nil)
        case .enabled, .requiresApproval:
            do {
                try service.unregister()
            } catch {
                return UpdateResult(
                    isEnabled: service.status == .enabled || service.status == .requiresApproval,
                    statusText: "无法关闭登录启动：\(error.localizedDescription)"
                )
            }

            let stillEnabled = service.status == .enabled || service.status == .requiresApproval
            return UpdateResult(
                isEnabled: stillEnabled,
                statusText: stillEnabled ? "登录启动仍处于系统待批准状态；请检查系统设置“通用 › 登录项”。" : nil
            )
        @unknown default:
            return UpdateResult(
                isEnabled: false,
                statusText: "无法确认登录启动状态；请检查系统设置“通用 › 登录项”。"
            )
        }
    }

    private var approvalInstructions: String {
        "请在系统设置“通用 › 登录项”中允许 NucLED 登录时打开。"
    }
}
