import AppKit
import OSLog
import SwiftUI

/// Owns the status item and the popover that contains the SwiftUI controls.
/// AppKit handles the click directly so opening the panel does not depend on
/// SwiftUI MenuBarExtra label hit-testing.
@MainActor
final class MenuBarController: NSObject {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let logger = Logger(subsystem: "local.nucled.MenuBar", category: "StatusItem")

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover()
        logger.info("Menu bar status item configured")
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = Self.makeSkullImage()
        button.imagePosition = .imageOnly
        button.toolTip = AppText.localized("menubar.tooltip")
        button.setAccessibilityLabel(AppText.localized("menubar.accessibility.label"))
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 330, height: 440)
        popover.contentViewController = NSHostingController(rootView: MenuBarPanel(model: model))
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            logger.info("Menu bar status item clicked; closing popover")
            popover.performClose(sender)
        } else {
            logger.info("Menu bar status item clicked; opening popover")
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private static func makeSkullImage() -> NSImage {
        // Keep the image canvas at the standard 18 pt menu-bar size, with a
        // little breathing room so the custom silhouette has the same visual
        // weight as neighboring system status icons.
        let renderer = ImageRenderer(
            content: HadesSkullSymbol()
                .frame(width: 16, height: 16)
                .frame(width: 18, height: 18)
        )
        renderer.scale = 2
        if let image = renderer.nsImage {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }
        let fallback = NSImage(
            systemSymbolName: "skull",
            accessibilityDescription: AppText.localized("menubar.skull.fallback.description")
        ) ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }
}
