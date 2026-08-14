import AppKit
import Foundation

enum ReminderContent: Equatable {
    case occurrence(String)
    case dailyStatus
    case dailyReview
}

@MainActor
final class ReminderService: ObservableObject {
    @Published private(set) var now = Date()
    @Published var presentedContent: ReminderContent = .dailyStatus

    let storage: StorageService
    let notifications: NotificationService
    let loginItem: LoginItemService

    private var timer: Timer?
    private var started = false
    private var currentDayKey = ""
    private var lastReminderAt: [String: Date] = [:]
    private var manualSnoozeUntil: [String: Date] = [:]
    private var dailyReviewedDay: String?
    private lazy var reminderWindow = ReminderWindowController(service: self)

    init(
        storage: StorageService,
        notifications: NotificationService = NotificationService(),
        loginItem: LoginItemService = LoginItemService()
    ) {
        self.storage = storage
        self.notifications = notifications
        self.loginItem = loginItem
    }

    var presentedOccurrence: DoseOccurrence? {
        guard case .occurrence(let id) = presentedContent else { return nil }
        return storage.occurrence(id: id, near: now)
    }

    func start() {
        guard !started else { return }
        started = true
        currentDayKey = DateSupport.dayKey(for: .now)
        notifications.configure()
        notifications.onNotificationOpened = { [weak self] occurrenceID in
            guard let self else { return }
            if !occurrenceID.isEmpty {
                self.showOccurrence(id: occurrenceID)
            } else {
                _ = self.reconcile(force: true)
            }
        }
        notifications.requestAuthorizationIfNeeded()

        if storage.settings.launchAtLoginDesired && !loginItem.isEnabled {
            loginItem.setEnabled(true)
        }

        observeSystemEvents()
        scheduleNotifications()
        let showedOverdue = reconcile(force: true)
        if !showedOverdue && storage.settings.showTodayAtLaunch {
            presentedContent = .dailyStatus
            reminderWindow.show()
        }

        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func status(for occurrence: DoseOccurrence) -> DoseOccurrenceStatus {
        occurrence.status(at: now)
    }

    func confirm(occurrenceID: String) {
        guard let occurrence = storage.occurrence(id: occurrenceID, near: now) else { return }
        storage.confirm(occurrence, at: now)
        notifications.removeDoseNotification(occurrenceID: occurrence.id)
        clearReminderState(for: occurrence.id)
        reminderWindow.close()
        scheduleNotifications()
        _ = reconcile(force: true)
    }

    func skip(occurrenceID: String) {
        guard let occurrence = storage.occurrence(id: occurrenceID, near: now) else { return }
        storage.skip(occurrence, at: now)
        notifications.removeDoseNotification(occurrenceID: occurrence.id)
        clearReminderState(for: occurrence.id)
        reminderWindow.close()
        scheduleNotifications()
        _ = reconcile(force: true)
    }

    func undoRecord(occurrenceID: String) {
        storage.removeRecord(id: occurrenceID)
        scheduleNotifications()
        _ = reconcile(force: false)
    }

    func recordAsNeeded(planID: UUID) {
        _ = storage.recordAsNeeded(planID: planID, at: now)
    }

    func snooze(occurrenceID: String) {
        manualSnoozeUntil[occurrenceID] = Calendar.current.date(
            byAdding: .minute,
            value: storage.settings.repeatIntervalMinutes,
            to: now
        )
        lastReminderAt[occurrenceID] = now
        reminderWindow.close()
    }

    func dismissWindow() {
        reminderWindow.close()
    }

    func showOccurrence(id: String) {
        guard let occurrence = storage.occurrence(id: id, near: now) else { return }
        switch occurrence.status(at: now) {
        case .taken, .skipped: return
        case .pending, .overdue:
            presentedContent = .occurrence(id)
            reminderWindow.show()
        }
    }

    func dataDidChange() {
        now = .now
        scheduleNotifications()
        _ = reconcile(force: true)
    }

    func settingsDidChange() {
        now = .now
        scheduleNotifications()
        _ = reconcile(force: false)
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func tick() {
        now = .now
        let newDayKey = DateSupport.dayKey(for: now)
        if newDayKey != currentDayKey {
            currentDayKey = newDayKey
            lastReminderAt.removeAll()
            manualSnoozeUntil.removeAll()
            dailyReviewedDay = nil
            scheduleNotifications()
        }
        let showedDailyReview = performDailyReviewIfNeeded()
        if !showedDailyReview {
            _ = reconcile(force: false)
        }
    }

    @discardableResult
    private func reconcile(force: Bool) -> Bool {
        now = .now
        guard let earliest = storage.overdueOccurrences(at: now).first else { return false }
        let key = earliest.id
        if let snooze = manualSnoozeUntil[key], now < snooze { return false }

        let shouldRepeat: Bool
        if force || lastReminderAt[key] == nil {
            shouldRepeat = true
        } else if storage.settings.repeatRemindersEnabled,
                  let last = lastReminderAt[key],
                  now.timeIntervalSince(last) >= Double(storage.settings.repeatIntervalMinutes * 60) {
            shouldRepeat = true
        } else if let snooze = manualSnoozeUntil[key], now >= snooze {
            shouldRepeat = true
        } else {
            shouldRepeat = false
        }

        guard shouldRepeat else { return false }
        lastReminderAt[key] = now
        manualSnoozeUntil.removeValue(forKey: key)
        showOccurrence(id: key)
        if storage.settings.notificationsEnabled,
           now.timeIntervalSince(earliest.scheduledTime) > 60 {
            notifications.sendDoseReminder(earliest)
        }
        return true
    }

    private func performDailyReviewIfNeeded() -> Bool {
        guard storage.settings.eveningCheckEnabled else { return false }
        let key = DateSupport.dayKey(for: now)
        guard dailyReviewedDay != key else { return false }
        let checkTime = DateSupport.time(on: now, minutes: storage.settings.eveningCheckMinutes)
        guard now >= checkTime else { return false }
        dailyReviewedDay = key

        let summary = storage.summary(for: now)
        guard summary.scheduledCount > 0 else { return false }
        if summary.resolvedCount == summary.scheduledCount {
            if summary.completedCount == summary.scheduledCount,
               storage.settings.notificationsEnabled {
                notifications.sendDailyComplete(completed: summary.completedCount)
            }
            return false
        }
        presentedContent = .dailyReview
        reminderWindow.show()
        return true
    }

    private func scheduleNotifications() {
        notifications.scheduleDoseNotifications(
            for: storage.upcomingOccurrences(from: now, days: 7),
            enabled: storage.settings.notificationsEnabled
        )
    }

    private func clearReminderState(for occurrenceID: String) {
        lastReminderAt.removeValue(forKey: occurrenceID)
        manualSnoozeUntil.removeValue(forKey: occurrenceID)
    }

    private func observeSystemEvents() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemTimeChanged),
            name: NSNotification.Name.NSSystemTimeZoneDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemTimeChanged),
            name: NSNotification.Name.NSSystemClockDidChange,
            object: nil
        )
    }

    @objc private func systemDidWake() {
        now = .now
        _ = reconcile(force: true)
        scheduleNotifications()
    }

    @objc private func appDidBecomeActive() {
        now = .now
        _ = reconcile(force: false)
    }

    @objc private func systemTimeChanged() {
        now = .now
        currentDayKey = DateSupport.dayKey(for: now)
        scheduleNotifications()
        _ = reconcile(force: true)
    }
}
