import SwiftUI

/// Compact status item label for the menu bar scene.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HadesSkullSymbol()
            .foregroundStyle(model.isLEDEnabled == true ? Color.primary : Color.secondary)
            .frame(width: 18, height: 18)
            .frame(width: 24, height: 22)
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let isLEDEnabled = model.isLEDEnabled else {
            return AppText.localized("menubar.accessibility.status.unknown")
        }
        return isLEDEnabled
            ? AppText.localized("menubar.accessibility.status.enabled")
            : AppText.localized("menubar.accessibility.status.disabled")
    }
}
