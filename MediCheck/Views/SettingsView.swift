import SwiftUI
import UserNotifications

struct SettingsView: View {
    @ObservedObject var service: ReminderService
    @ObservedObject var storage: StorageService

    var body: some View {
        Form {
            Section("服药时间") {
                ForEach(DoseType.allCases) { dose in
                    DatePicker(dose.displayName, selection: timeBinding(for: dose), displayedComponents: .hourAndMinute)
                }
            }

            Section("提醒设置") {
                Toggle("系统通知", isOn: settingBinding(\.notificationsEnabled))
                if service.notifications.authorizationStatus == .denied {
                    HStack {
                        Text("通知权限已关闭")
                            .foregroundStyle(.red)
                        Spacer()
                        Button("打开系统设置") { service.openNotificationSettings() }
                    }
                }
                Toggle("未确认重复提醒", isOn: settingBinding(\.repeatRemindersEnabled))
                Picker("重复提醒间隔", selection: settingBinding(\.repeatIntervalMinutes)) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) 分钟").tag($0) }
                }
                Toggle("晚间检查", isOn: settingBinding(\.eveningCheckEnabled))
                DatePicker("晚间检查时间", selection: eveningCheckBinding, displayedComponents: .hourAndMinute)
                    .disabled(!storage.settings.eveningCheckEnabled)
            }

            Section("系统") {
                Toggle("登录时自动启动", isOn: loginItemBinding)
                Toggle("启动时显示今日状态", isOn: settingBinding(\.showTodayAtLaunch))
                if let error = service.loginItem.errorMessage {
                    Text(error).foregroundStyle(.red)
                    Button("打开登录项设置") { service.loginItem.openLoginItemsSettings() }
                }
            }

            Section {
                Text("MediCheck 只记录用户确认，不提供剂量、补服或其他医疗建议。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
        .padding(.top, 8)
        .onAppear {
            service.notifications.refreshAuthorizationStatus()
            service.loginItem.refresh()
        }
    }

    private func timeBinding(for dose: DoseType) -> Binding<Date> {
        Binding(
            get: { DateSupport.time(on: .now, minutes: storage.settings.minutes(for: dose)) },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                storage.updateSettings { $0.doseMinutes[dose] = minutes }
                service.settingsDidChange(scheduleChanged: true)
            }
        )
    }

    private var eveningCheckBinding: Binding<Date> {
        Binding(
            get: { DateSupport.time(on: .now, minutes: storage.settings.eveningCheckMinutes) },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                storage.updateSettings { $0.eveningCheckMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0) }
                service.settingsDidChange()
            }
        )
    }

    private func settingBinding<Value>(_ keyPath: WritableKeyPath<MedicationSettings, Value>) -> Binding<Value> {
        Binding(
            get: { storage.settings[keyPath: keyPath] },
            set: { value in
                storage.updateSettings { $0[keyPath: keyPath] = value }
                service.settingsDidChange()
            }
        )
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { service.loginItem.isEnabled },
            set: { enabled in
                service.loginItem.setEnabled(enabled)
                storage.updateSettings { $0.launchAtLoginDesired = service.loginItem.isEnabled }
            }
        )
    }
}

