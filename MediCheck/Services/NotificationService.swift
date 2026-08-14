import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var onNotificationOpened: ((String) -> Void)?
    private let center = UNUserNotificationCenter.current()

    func configure() {
        center.delegate = self
        refreshAuthorizationStatus()
    }

    func requestAuthorizationIfNeeded() {
        Task {
            let settings = await center.notificationSettings()
            authorizationStatus = settings.authorizationStatus
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            refreshAuthorizationStatus()
        }
    }

    func refreshAuthorizationStatus() {
        Task {
            authorizationStatus = await center.notificationSettings().authorizationStatus
        }
    }

    func scheduleDoseNotifications(for record: DailyRecord, enabled: Bool) {
        let identifiers = DoseType.allCases.map { notificationID(for: $0, dayKey: record.id) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        guard enabled else { return }

        for dose in DoseType.allCases {
            guard let entry = record.entries[dose], entry.confirmedTime == nil, entry.scheduledTime > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "💊 \(dose.displayName)提醒"
            content.body = "今天的\(dose.displayName)还没有确认。"
            content.sound = .default
            content.userInfo = ["dose": dose.rawValue]

            var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: entry.scheduledTime)
            components.timeZone = .current
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: notificationID(for: dose, dayKey: record.id), content: content, trigger: trigger)
            center.add(request)
        }
    }

    func sendDoseReminder(_ dose: DoseType) {
        let content = UNMutableNotificationContent()
        content.title = "💊 \(dose.displayName)提醒"
        content.body = "今天的\(dose.displayName)还没有确认。"
        content.sound = .default
        content.userInfo = ["dose": dose.rawValue]
        center.add(UNNotificationRequest(identifier: "immediate.\(UUID().uuidString)", content: content, trigger: nil))
    }

    func sendEveningComplete() {
        let content = UNMutableNotificationContent()
        content.title = "✅ 今天的服药记录已全部完成"
        content.body = "早、中、晚三次均已确认。"
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "evening.complete.\(UUID().uuidString)", content: content, trigger: nil))
    }

    func removeDoseNotification(_ dose: DoseType, dayKey: String) {
        center.removePendingNotificationRequests(withIdentifiers: [notificationID(for: dose, dayKey: dayKey)])
    }

    private func notificationID(for dose: DoseType, dayKey: String) -> String {
        "dose.\(dayKey).\(dose.rawValue)"
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let dose = response.notification.request.content.userInfo["dose"] as? String
        Task { @MainActor [weak self] in
            self?.onNotificationOpened?(dose ?? "")
        }
        completionHandler()
    }
}

