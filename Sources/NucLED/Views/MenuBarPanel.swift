import SwiftUI

/// Main popover content hosted by the AppKit status-item controller.
struct MenuBarPanel: View {
    @ObservedObject var model: AppModel

    private var ledBinding: Binding<Bool> {
        Binding(
            get: { model.isLEDEnabled ?? false },
            set: { _ in model.toggleLED() }
        )
    }

    private var scheduleBinding: Binding<Bool> {
        Binding(
            get: { model.isScheduleEnabled },
            set: { model.setScheduleEnabled($0) }
        )
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { model.isLoginItemEnabled },
            set: { model.setLoginItemEnabled($0) }
        )
    }

    private var onTimeBinding: Binding<Date> {
        Binding(
            get: { model.onTime },
            set: { model.setOnTime($0) }
        )
    }

    private var offTimeBinding: Binding<Date> {
        Binding(
            get: { model.offTime },
            set: { model.setOffTime($0) }
        )
    }

    private var hasError: Bool {
        let text = model.statusText.lowercased()
        let errorTerms = ["失败", "错误", "不可用", "未连接", "未接入", "未生效", "error", "failed", "unavailable", "denied"]
        return errorTerms.contains { text.contains($0) }
    }

    private var statusColor: Color {
        if hasError { return .red }
        guard let isLEDEnabled = model.isLEDEnabled else { return .secondary }
        return isLEDEnabled ? .green : .secondary
    }

    private var statusDescription: String {
        if !model.statusText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return model.statusText
        }
        guard let isLEDEnabled = model.isLEDEnabled else { return "设备状态未知" }
        return isLEDEnabled ? "控制就绪 · LED 模式已启用" : "控制就绪 · LED 模式已停用"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            ledControl

            nextAction

            Divider()

            scheduleControl

            loginItemControl

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 330)
    }

    private var header: some View {
        HStack(spacing: 12) {
            HadesSkullBrandMark()
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("冥王 LED")
                    .font(.headline)
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var ledControl: some View {
        Toggle(isOn: ledBinding) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LED 总开关")
                    .font(.body.weight(.medium))
                Text("统一控制全部可控区域的指示灯模式")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(model.isLEDEnabled == nil || !model.canControlLED || model.isHardwareBusy)
        .help(model.canControlLED ? "启用或停用 LED 指示灯模式" : statusDescription)
    }

    private var scheduleControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("每日定时开关", isOn: scheduleBinding)

            HStack(spacing: 10) {
                timePicker(title: "开启时间", color: .green, selection: onTimeBinding)
                timePicker(title: "关闭时间", color: .orange, selection: offTimeBinding)
            }
        }
    }

    private func timePicker(title: String, color: Color, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.field)
                .accessibilityLabel(title)
                .onChange(of: selection.wrappedValue) { _ in
                    MenuBarTextEditing.commitAndDefocus()
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private var nextAction: some View {
        HStack(spacing: 7) {
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(nextActionPrompt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.leading, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var nextActionPrompt: String {
        model.nextActionText == "定时已关闭"
            ? "每日定时未开启，没有待执行动作"
            : "下次：\(model.nextActionText)"
    }

    private var loginItemControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("登录时启动", isOn: loginItemBinding)
                .help("登录 macOS 账户后自动打开冥王 LED")

            if let notice = model.loginItemStatusText {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack {
            Label("退出后暂停，重新打开后继续", systemImage: "pause.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("退出") {
                model.quit()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .help("退出后定时计划暂停；重新打开应用后继续")
            .keyboardShortcut("q")
        }
    }
}
