import AppKit
import SwiftUI

/// A single-line localized time field. `NSDatePicker` keeps a selected time
/// segment highlighted after editing ends on some macOS versions, so this
/// field uses AppKit's text-editing delegate to clear the real field editor
/// selection as part of the end-editing callback.
struct TimeField: NSViewRepresentable {
    @Binding var selection: Date

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: Self.formatted(selection))
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.commit(_:))
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        field.textColor = .labelColor
        field.maximumNumberOfLines = 1
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.selection = $selection
        guard !context.coordinator.isEditing else { return }

        let value = Self.formatted(selection)
        if field.stringValue != value {
            field.stringValue = value
        }
    }

    private static func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func parsed(_ text: String, basedOn currentDate: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        guard let parsedDate = formatter.date(from: text) else { return nil }

        let calendar = Calendar.autoupdatingCurrent
        let parts = calendar.dateComponents([.hour, .minute], from: parsedDate)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: currentDate)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var selection: Binding<Date>
        var isEditing = false
        private weak var activeEditor: NSTextView?

        init(selection: Binding<Date>) {
            self.selection = selection
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            isEditing = true
            activeEditor = field.currentEditor() as? NSTextView
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            commitValue(field)
            isEditing = false
            clearSelection(in: field)
        }

        @objc func commit(_ sender: NSTextField) {
            commitValue(sender)
            sender.window?.makeFirstResponder(nil)
        }

        private func commitValue(_ field: NSTextField) {
            if let value = TimeField.parsed(field.stringValue, basedOn: selection.wrappedValue) {
                selection.wrappedValue = value
                field.stringValue = TimeField.formatted(value)
            } else {
                field.stringValue = TimeField.formatted(selection.wrappedValue)
            }
        }

        private func clearSelection(in field: NSTextField) {
            let editor = (field.currentEditor() as? NSTextView)
                ?? (field.window?.fieldEditor(false, for: field) as? NSTextView)
                ?? activeEditor
            guard let editor else {
                activeEditor = nil
                return
            }

            let end = (editor.string as NSString).length
            editor.setSelectedRange(NSRange(location: end, length: 0))
            DispatchQueue.main.async { [weak editor] in
                guard let editor else { return }
                let end = (editor.string as NSString).length
                editor.setSelectedRange(NSRange(location: end, length: 0))
            }
            activeEditor = nil
        }
    }
}
