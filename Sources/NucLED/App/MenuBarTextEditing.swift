import AppKit
import Foundation

/// Commits edits in AppKit-backed SwiftUI fields after the user pauses, then
/// removes first-responder focus so segmented fields (such as DatePicker's
/// hour/minute editor) do not keep a blue text selection visible.
@MainActor
enum MenuBarTextEditing {
    private static var pendingDefocus: DispatchWorkItem?

    /// Debounces field defocus so a multi-digit time edit can finish before
    /// the field resigns focus. Call when the bound time changes.
    static func commitAndDefocus(afterIdle delay: TimeInterval = 0.75) {
        pendingDefocus?.cancel()

        // Keep the exact popover window captured at edit time. If it closes
        // before the debounce expires, the visibility check makes this a no-op.
        guard let window = NSApp.keyWindow else { return }

        let work = DispatchWorkItem { [weak window] in
            guard let window, window.isVisible else { return }
            window.endEditing(for: nil)
            _ = window.makeFirstResponder(nil)
        }

        pendingDefocus = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
