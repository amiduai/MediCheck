import Foundation

@MainActor
final class StorageService: ObservableObject {
    @Published private(set) var settings: MedicationSettings
    @Published private(set) var records: [String: DailyRecord]

    private let defaults: UserDefaults
    private let settingsKey = "medicheck.settings.v1"
    private let recordsKey = "medicheck.records.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: settingsKey),
           let value = try? decoder.decode(MedicationSettings.self, from: data) {
            settings = value
        } else {
            settings = .defaults
        }
        if let data = defaults.data(forKey: recordsKey),
           let value = try? decoder.decode([String: DailyRecord].self, from: data) {
            records = value
        } else {
            records = [:]
        }
    }

    func updateSettings(_ change: (inout MedicationSettings) -> Void) {
        change(&settings)
        persistSettings()
    }

    @discardableResult
    func ensureRecord(for date: Date = .now, calendar: Calendar = .current) -> DailyRecord {
        let key = DateSupport.dayKey(for: date, calendar: calendar)
        if let existing = records[key] { return existing }

        let day = calendar.startOfDay(for: date)
        let entries = Dictionary(uniqueKeysWithValues: DoseType.allCases.map { dose in
            (dose, DoseEntry(
                doseType: dose,
                scheduledTime: DateSupport.time(on: day, minutes: settings.minutes(for: dose), calendar: calendar),
                confirmedTime: nil
            ))
        })
        let record = DailyRecord(id: key, day: day, entries: entries)
        records[key] = record
        trimAndPersistRecords(referenceDate: date, calendar: calendar)
        return record
    }

    func refreshTodaySchedule(at date: Date = .now, calendar: Calendar = .current) {
        var record = ensureRecord(for: date, calendar: calendar)
        for dose in DoseType.allCases {
            guard var entry = record.entries[dose] else { continue }
            entry.scheduledTime = DateSupport.time(on: date, minutes: settings.minutes(for: dose), calendar: calendar)
            record.entries[dose] = entry
        }
        records[record.id] = record
        persistRecords()
    }

    func record(for date: Date = .now, calendar: Calendar = .current) -> DailyRecord {
        ensureRecord(for: date, calendar: calendar)
    }

    func confirm(_ dose: DoseType, at confirmationDate: Date = .now, calendar: Calendar = .current) {
        var record = ensureRecord(for: confirmationDate, calendar: calendar)
        guard var entry = record.entries[dose] else { return }
        entry.confirmedTime = confirmationDate
        record.entries[dose] = entry
        records[record.id] = record
        persistRecords()
    }

    func status(for dose: DoseType, at now: Date = .now, calendar: Calendar = .current) -> DoseStatus {
        let record = ensureRecord(for: now, calendar: calendar)
        guard let entry = record.entries[dose] else { return .overdue }
        return DateSupport.status(entry: entry, now: now)
    }

    func recentRecords(days: Int, endingAt date: Date = .now, calendar: Calendar = .current) -> [DailyRecord] {
        (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { return nil }
            return recordSnapshot(for: day, calendar: calendar)
        }
    }

    func recordSnapshot(for date: Date, calendar: Calendar = .current) -> DailyRecord {
        let key = DateSupport.dayKey(for: date, calendar: calendar)
        if let existing = records[key] { return existing }
        let start = calendar.startOfDay(for: date)
        let entries = Dictionary(uniqueKeysWithValues: DoseType.allCases.map { dose in
            (dose, DoseEntry(
                doseType: dose,
                scheduledTime: DateSupport.time(on: start, minutes: settings.minutes(for: dose), calendar: calendar),
                confirmedTime: nil
            ))
        })
        return DailyRecord(id: key, day: start, entries: entries)
    }

    private func trimAndPersistRecords(referenceDate: Date, calendar: Calendar) {
        let cutoff = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
        records = records.filter { $0.value.day >= cutoff }
        persistRecords()
    }

    private func persistSettings() {
        if let data = try? encoder.encode(settings) { defaults.set(data, forKey: settingsKey) }
    }

    private func persistRecords() {
        if let data = try? encoder.encode(records) { defaults.set(data, forKey: recordsKey) }
    }
}
