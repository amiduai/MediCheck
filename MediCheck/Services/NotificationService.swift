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

    func scheduleDoseNotifications(for occurrences: [DoseOccurrence], enabled: Bool) {
        center.removeAllPendingNotificationRequests()
        guard enabled else { return }

        for occurrence in occurrences.prefix(48) {
            let content = UNMutableNotificationContent()
            content.title = "💊 \(occurrence.medication.name)"
            content.body = notificationBody(for: occurrence)
            content.sound = .default
            content.userInfo = ["occurrenceID": occurrence.id]

            var components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: occurrence.scheduledTime
            )
            components.timeZone = .current
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(
                identifier: notificationID(for: occurrence.id),
                content: content,
                trigger: trigger
            ))
        }
    }

    func sendDoseReminder(_ occurrence: DoseOccurrence) {
        let content = UNMutableNotificationContent()
        content.title = "💊 \(occurrence.medication.name)尚未确认"
        content.body = notificationBody(for: occurrence)
        content.sound = .default
        content.userInfo = ["occurrenceID": occurrence.id]
        center.add(UNNotificationRequest(
            identifier: "immediate.\(UUID().uuidString)",
            content: content,
            trigger: nil
        ))
    }

    func sendDailyComplete(completed: Int) {
        let content = UNMutableNotificationContent()
        content.title = "✅ 今天的计划用药已完成"
        content.body = "已确认 \(completed) 次计划用药。"
        content.sound = .default
        center.add(UNNotificationRequest(
            identifier: "daily.complete.\(UUID().uuidString)",
            content: content,
            trigger: nil
        ))
    }

    func removeDoseNotification(occurrenceID: String) {
        center.removePendingNotificationRequests(withIdentifiers: [notificationID(for: occurrenceID)])
    }

    private func notificationBody(for occurrence: DoseOccurrence) -> String {
        let detail = occurrence.medication.detailLine
        return detail.isEmpty ? "请按计划确认本次用药。" : detail
    }

    private func notificationID(for occurrenceID: String) -> String {
        "medicheck.dose.\(occurrenceID)"
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
        let occurrenceID = response.notification.request.content.userInfo["occurrenceID"] as? String
        Task { @MainActor [weak self] in
            self?.onNotificationOpened?(occurrenceID ?? "")
        }
        completionHandler()
    }
}
