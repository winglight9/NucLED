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
        guard let isLEDEnabled = model.isLEDEnabled else { return "冥王 LED 状态未知" }
        return isLEDEnabled ? "冥王 LED 模式已启用" : "冥王 LED 模式已停用"
    }
}
