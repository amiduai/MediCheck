import SwiftUI
import UserNotifications

struct SettingsView: View {
    @ObservedObject var service: ReminderService
    @ObservedObject var storage: StorageService

    var body: some View {
        Form {
            Section("提醒") {
                Toggle("系统通知", isOn: settingBinding(\.notificationsEnabled))
                if service.notifications.authorizationStatus == .denied {
                    HStack {
                        Text("通知权限已关闭")
                            .foregroundStyle(.red)
                        Spacer()
                        Button("打开系统设置") { service.openNotificationSettings() }
                    }
                }
                Toggle("未确认时重复提醒", isOn: settingBinding(\.repeatRemindersEnabled))
                Picker("重复提醒间隔", selection: settingBinding(\.repeatIntervalMinutes)) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) 分钟").tag($0) }
                }
                .disabled(!storage.settings.repeatRemindersEnabled)
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

            Section("数据与隐私") {
                Label("药品、计划和记录只保存在这台 Mac", systemImage: "lock.fill")
                Text("MediCheck 不联网、无账号、无广告。删除应用前如需保留数据，请先等待后续版本提供导出功能。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                LabeledContent("版本", value: "2.0")
                Text("MediCheck 只执行用户录入的提醒和记录，不提供诊断、剂量、相互作用、漏服补服或其他医疗建议。用药方案请以医生或药师意见为准。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 570)
        .padding(.top, 8)
        .onAppear {
            service.notifications.refreshAuthorizationStatus()
            service.loginItem.refresh()
        }
    }

    private var eveningCheckBinding: Binding<Date> {
        Binding(
            get: { DateSupport.time(on: .now, minutes: storage.settings.eveningCheckMinutes) },
            set: { date in
                storage.updateSettings { $0.eveningCheckMinutes = DateSupport.minutesSinceMidnight(for: date) }
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
