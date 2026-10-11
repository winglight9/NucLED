import AppKit
import Combine
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
    private var stateObservation: AnyCancellable?

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover()
        observeLEDState()
        logger.info("Menu bar status item configured")
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = Self.makeSkullImage()
        button.imagePosition = .imageOnly
        button.toolTip = "冥王 LED"
        button.setAccessibilityLabel("冥王 LED 状态与控制")
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateTintColor(for: model.isLEDEnabled)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 330, height: 440)
        popover.contentViewController = NSHostingController(rootView: MenuBarPanel(model: model))
    }

    private func observeLEDState() {
        stateObservation = model.$isLEDEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateTintColor(for: state)
            }
    }

    private func updateTintColor(for state: Bool?) {
        guard let button = statusItem.button else { return }
        switch state {
        case .some(true):
            button.contentTintColor = .labelColor
        case .some(false):
            button.contentTintColor = .secondaryLabelColor
        case .none:
            button.contentTintColor = .tertiaryLabelColor
        }
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
        let renderer = ImageRenderer(content: HadesSkullSymbol().frame(width: 18, height: 18))
        renderer.scale = 2
        if let image = renderer.nsImage {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }
        return NSImage(systemSymbolName: "skull", accessibilityDescription: "冥王 LED") ?? NSImage()
    }
}
