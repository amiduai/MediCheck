import Foundation

struct MedicationSettings: Codable, Equatable {
    var doseMinutes: [DoseType: Int]
    var notificationsEnabled: Bool
    var repeatRemindersEnabled: Bool
    var repeatIntervalMinutes: Int
    var eveningCheckEnabled: Bool
    var eveningCheckMinutes: Int
    var launchAtLoginDesired: Bool
    var showTodayAtLaunch: Bool

    static let defaults = MedicationSettings(
        doseMinutes: Dictionary(uniqueKeysWithValues: DoseType.allCases.map { ($0, $0.defaultMinutes) }),
        notificationsEnabled: true,
        repeatRemindersEnabled: true,
        repeatIntervalMinutes: 10,
        eveningCheckEnabled: true,
        eveningCheckMinutes: 22 * 60 + 30,
        launchAtLoginDesired: true,
        showTodayAtLaunch: true
    )

    func minutes(for dose: DoseType) -> Int {
        doseMinutes[dose] ?? dose.defaultMinutes
    }
}

