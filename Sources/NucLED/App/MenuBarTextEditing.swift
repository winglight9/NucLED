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

        // DatePicker's segmented editor can retain its field editor after the
        // value binding changes. Capture the popover's key window now, then
        // clear the editor selection before asking AppKit to end editing.
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isKeyWindow) else { return }

        let work = DispatchWorkItem { [weak window] in
            guard let window, window.isVisible else { return }
            clearFieldEditorSelection(in: window)
            window.endEditing(for: nil)
            _ = window.makeFirstResponder(nil)

            // SwiftUI may restore DatePicker's first responder during the
            // same update cycle. Reapply after it has processed that update.
            DispatchQueue.main.async { [weak window] in
                guard let window, window.isVisible else { return }
                clearFieldEditorSelection(in: window)
                window.endEditing(for: nil)
                _ = window.makeFirstResponder(nil)
            }
        }

        pendingDefocus = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static func clearFieldEditorSelection(in window: NSWindow) {
        guard let editor = window.firstResponder as? NSTextView, editor.isFieldEditor else { return }
        let end = (editor.string as NSString).length
        editor.setSelectedRange(NSRange(location: end, length: 0))
    }
}
