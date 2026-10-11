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
        let errorTerms = [
            "失败", "错误", "不可用", "未连接", "未接入", "未生效",
            "error", "failed", "unavailable", "denied",
            "失敗", "エラー", "利用できません", "接続されていません", "反映されません", "できません",
            "실패", "오류", "사용할 수 없습니다", "연결되지 않았습니다", "적용되지 않았습니다", "할 수 없습니다", "거부"
        ]
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
        guard let isLEDEnabled = model.isLEDEnabled else {
            return AppText.localized("menu.status.unknown")
        }
        return AppText.localized(
            isLEDEnabled ? "menu.status.ready.enabled" : "menu.status.ready.disabled"
        )
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
                Text(AppText.localized("menu.app.name"))
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
                Text(AppText.localized("menu.led.title"))
                    .font(.body.weight(.medium))
                Text(AppText.localized("menu.led.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(model.isLEDEnabled == nil || !model.canControlLED || model.isHardwareBusy)
        .help(model.canControlLED ? AppText.localized("menu.led.help") : statusDescription)
    }

    private var scheduleControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(AppText.localized("menu.schedule.title"), isOn: scheduleBinding)

            HStack(spacing: 10) {
                timePicker(
                    title: AppText.localized("menu.schedule.time.on"),
                    color: .green,
                    selection: onTimeBinding
                )
                timePicker(
                    title: AppText.localized("menu.schedule.time.off"),
                    color: .orange,
                    selection: offTimeBinding
                )
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
        model.isScheduleEnabled
            ? AppText.localized("menu.nextAction.upcoming", model.nextActionText)
            : AppText.localized("menu.nextAction.disabled")
    }

    private var loginItemControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(AppText.localized("menu.login.title"), isOn: loginItemBinding)
                .help(AppText.localized("menu.login.help"))

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
            Label(AppText.localized("menu.footer.quitReminder"), systemImage: "pause.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button(AppText.localized("menu.action.quit")) {
                model.quit()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .help(AppText.localized("menu.action.quit.help"))
            .keyboardShortcut("q")
        }
    }
}
