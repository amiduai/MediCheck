import AppKit
import Foundation

enum ReminderContent: Equatable {
    case dose(DoseType)
    case dailyStatus
    case eveningReview
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
    private var eveningCheckedDay: String?
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

    func start() {
        guard !started else { return }
        started = true
        currentDayKey = DateSupport.dayKey(for: .now)
        storage.ensureRecord()
        notifications.configure()
        notifications.onNotificationOpened = { [weak self] rawDose in
            guard let self else { return }
            if let dose = DoseType(rawValue: rawDose) {
                self.showDose(dose)
            } else {
                self.reconcile(force: true)
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

    func status(for dose: DoseType) -> DoseStatus {
        storage.status(for: dose, at: now)
    }

    func confirm(_ dose: DoseType) {
        let dayKey = DateSupport.dayKey(for: now)
        storage.confirm(dose, at: now)
        notifications.removeDoseNotification(dose, dayKey: dayKey)
        lastReminderAt.removeValue(forKey: reminderKey(dose))
        manualSnoozeUntil.removeValue(forKey: reminderKey(dose))
        reminderWindow.close()
        _ = reconcile(force: true)
    }

    func snooze(_ dose: DoseType) {
        let key = reminderKey(dose)
        manualSnoozeUntil[key] = Calendar.current.date(
            byAdding: .minute,
            value: storage.settings.repeatIntervalMinutes,
            to: now
        )
        lastReminderAt[key] = now
        reminderWindow.close()
    }

    func dismissWindow() {
        reminderWindow.close()
    }

    func showDose(_ dose: DoseType) {
        guard case .done = storage.status(for: dose, at: now) else {
            presentedContent = .dose(dose)
            reminderWindow.show()
            return
        }
    }

    func settingsDidChange(scheduleChanged: Bool = false) {
        now = .now
        if scheduleChanged { storage.refreshTodaySchedule(at: now) }
        scheduleNotifications()
        _ = reconcile(force: scheduleChanged)
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
            eveningCheckedDay = nil
            storage.ensureRecord(for: now)
            scheduleNotifications()
        }
        let showedEveningReview = performEveningCheckIfNeeded()
        if !showedEveningReview {
            _ = reconcile(force: false)
        }
    }

    @discardableResult
    private func reconcile(force: Bool) -> Bool {
        now = .now
        let overdue = DoseType.allCases.filter {
            if case .overdue = storage.status(for: $0, at: now) { return true }
            return false
        }
        guard let earliest = overdue.first else { return false }

        let key = reminderKey(earliest)
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
        showDose(earliest)
        if storage.settings.notificationsEnabled,
           now.timeIntervalSince(storage.record(for: now).entries[earliest]?.scheduledTime ?? now) > 60 {
            notifications.sendDoseReminder(earliest)
        }
        return true
    }

    private func performEveningCheckIfNeeded() -> Bool {
        guard storage.settings.eveningCheckEnabled else { return false }
        let key = DateSupport.dayKey(for: now)
        guard eveningCheckedDay != key else { return false }
        let checkTime = DateSupport.time(on: now, minutes: storage.settings.eveningCheckMinutes)
        guard now >= checkTime else { return false }
        eveningCheckedDay = key
        let record = storage.record(for: now)
        if record.completedCount == DoseType.allCases.count {
            if storage.settings.notificationsEnabled { notifications.sendEveningComplete() }
            return false
        } else {
            presentedContent = .eveningReview
            reminderWindow.show()
            return true
        }
    }

    private func scheduleNotifications() {
        notifications.scheduleDoseNotifications(for: storage.record(for: now), enabled: storage.settings.notificationsEnabled)
    }

    private func reminderKey(_ dose: DoseType) -> String {
        "\(DateSupport.dayKey(for: now)).\(dose.rawValue)"
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
        storage.refreshTodaySchedule(at: now)
        scheduleNotifications()
        _ = reconcile(force: true)
    }
}
