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
                statusText: enabled ? AppText.localized("login.error.osVersionRequired") : nil
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
                    statusText: AppText.localized("login.error.installInApplications")
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
                    statusText: AppText.localized("login.error.enableFailed", error.localizedDescription)
                )
            }

            if service.status == .requiresApproval {
                return UpdateResult(isEnabled: true, statusText: approvalInstructions)
            }
            return service.status == .enabled
                ? UpdateResult(isEnabled: true, statusText: nil)
                : UpdateResult(
                    isEnabled: true,
                    statusText: AppText.localized("login.status.requestedCheckSettings")
                )
        @unknown default:
            return UpdateResult(
                isEnabled: false,
                statusText: AppText.localized("login.error.statusUnknown")
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
                    statusText: AppText.localized("login.error.disableFailed", error.localizedDescription)
                )
            }

            let stillEnabled = service.status == .enabled || service.status == .requiresApproval
            return UpdateResult(
                isEnabled: stillEnabled,
                statusText: stillEnabled ? AppText.localized("login.error.disableStillPending") : nil
            )
        @unknown default:
            return UpdateResult(
                isEnabled: false,
                statusText: AppText.localized("login.error.statusUnknown")
            )
        }
    }

    private var approvalInstructions: String {
        AppText.localized("login.status.approvalRequired")
    }
}
