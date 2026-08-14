import Foundation

@MainActor
final class StorageService: ObservableObject {
    @Published private(set) var settings: MedicationSettings
    @Published private(set) var medications: [Medication]
    @Published private(set) var plans: [MedicationPlan]
    @Published private(set) var doseRecords: [String: MedicationDoseRecord]

    private let defaults: UserDefaults
    private let settingsKeyV1 = "medicheck.settings.v1"
    private let recordsKeyV1 = "medicheck.records.v1"
    private let medicationsKey = "medicheck.medications.v2"
    private let plansKey = "medicheck.plans.v2"
    private let doseRecordsKey = "medicheck.doseRecords.v2"
    private let migrationKey = "medicheck.migration.v1ToV2.completed"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current, now: Date = .now) {
        self.defaults = defaults
        settings = Self.decode(MedicationSettings.self, key: settingsKeyV1, defaults: defaults, decoder: decoder) ?? .defaults
        medications = Self.decode([Medication].self, key: medicationsKey, defaults: defaults, decoder: decoder) ?? []
        plans = Self.decode([MedicationPlan].self, key: plansKey, defaults: defaults, decoder: decoder) ?? []
        doseRecords = Self.decode([String: MedicationDoseRecord].self, key: doseRecordsKey, defaults: defaults, decoder: decoder) ?? [:]
        migrateV1IfNeeded(calendar: calendar, now: now)
        normalizeScheduledRecordIDs(calendar: calendar)
    }

    var activeMedicationPlans: [(medication: Medication, plan: MedicationPlan)] {
        plans.compactMap { plan in
            guard let medication = medication(id: plan.medicationID) else { return nil }
            return (medication, plan)
        }
        .sorted { lhs, rhs in
            if lhs.plan.isEnabled != rhs.plan.isEnabled { return lhs.plan.isEnabled }
            return lhs.medication.name.localizedStandardCompare(rhs.medication.name) == .orderedAscending
        }
    }

    func updateSettings(_ change: (inout MedicationSettings) -> Void) {
        change(&settings)
        persist(settings, key: settingsKeyV1)
    }

    func medication(id: UUID) -> Medication? {
        medications.first { $0.id == id }
    }

    func plan(id: UUID) -> MedicationPlan? {
        plans.first { $0.id == id }
    }

    func plan(for medicationID: UUID) -> MedicationPlan? {
        plans.first { $0.medicationID == medicationID }
    }

    func saveMedication(_ medication: Medication, plan: MedicationPlan) {
        var normalizedPlan = plan
        normalizedPlan.medicationID = medication.id
        normalizedPlan.reminderMinutes = Array(Set(plan.reminderMinutes)).sorted()
        normalizedPlan.weekdays = Array(Set(plan.weekdays.filter { (1...7).contains($0) })).sorted()

        if let index = medications.firstIndex(where: { $0.id == medication.id }) {
            medications[index] = medication
        } else {
            medications.append(medication)
        }
        if let index = plans.firstIndex(where: { $0.id == normalizedPlan.id }) {
            plans[index] = normalizedPlan
        } else {
            plans.removeAll { $0.medicationID == medication.id }
            plans.append(normalizedPlan)
        }
        persistV2()
    }

    func setPlanEnabled(_ planID: UUID, enabled: Bool) {
        guard let index = plans.firstIndex(where: { $0.id == planID }) else { return }
        plans[index].isEnabled = enabled
        persist(plans, key: plansKey)
    }

    func deleteMedication(_ medicationID: UUID) {
        let planIDs = Set(plans.filter { $0.medicationID == medicationID }.map(\.id))
        medications.removeAll { $0.id == medicationID }
        plans.removeAll { $0.medicationID == medicationID }
        doseRecords = doseRecords.filter { _, record in
            record.medicationID != medicationID && !planIDs.contains(record.planID)
        }
        persistV2()
    }

    func summary(for date: Date, calendar: Calendar = .current) -> DailyMedicationSummary {
        let day = calendar.startOfDay(for: date)
        var occurrences: [DoseOccurrence] = []

        for plan in plans where plan.isScheduled(on: day, calendar: calendar) {
            guard let medication = medication(id: plan.medicationID) else { continue }
            for (slotIndex, minutes) in plan.reminderMinutes.sorted().enumerated() {
                let occurrenceID = DateSupport.occurrenceID(planID: plan.id, day: day, minutes: minutes, calendar: calendar)
                let record = doseRecords[occurrenceID]
                let scheduledTime = record?.scheduledTime ?? DateSupport.time(on: day, minutes: minutes, calendar: calendar)
                occurrences.append(DoseOccurrence(
                    id: occurrenceID,
                    slotIndex: slotIndex,
                    medication: medication,
                    plan: plan,
                    scheduledTime: scheduledTime,
                    record: record
                ))
            }
        }

        let existingIDs = Set(occurrences.map(\.id))
        let orphanedScheduledRecords = doseRecords.values.filter { record in
            guard record.source == .scheduled,
                  !existingIDs.contains(record.id),
                  let scheduledTime = record.scheduledTime else { return false }
            return calendar.isDate(scheduledTime, inSameDayAs: day)
        }
        for record in orphanedScheduledRecords {
            guard let medication = medication(id: record.medicationID),
                  let plan = plan(id: record.planID),
                  let scheduledTime = record.scheduledTime else { continue }
            occurrences.append(DoseOccurrence(
                id: record.id,
                slotIndex: -1,
                medication: medication,
                plan: plan,
                scheduledTime: scheduledTime,
                record: record
            ))
        }

        occurrences.sort {
            if $0.scheduledTime != $1.scheduledTime { return $0.scheduledTime < $1.scheduledTime }
            return $0.medication.name.localizedStandardCompare($1.medication.name) == .orderedAscending
        }

        let asNeeded = doseRecords.values.filter { record in
            record.source == .asNeeded && calendar.isDate(record.actionTime, inSameDayAs: day)
        }.sorted { $0.actionTime < $1.actionTime }

        return DailyMedicationSummary(day: day, occurrences: occurrences, asNeededRecords: asNeeded)
    }

    func occurrence(id: String, near date: Date = .now, calendar: Calendar = .current) -> DoseOccurrence? {
        for offset in -1...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            if let occurrence = summary(for: day, calendar: calendar).occurrences.first(where: { $0.id == id }) {
                return occurrence
            }
        }
        return nil
    }

    func upcomingOccurrences(from date: Date = .now, days: Int = 7, calendar: Calendar = .current) -> [DoseOccurrence] {
        (0..<max(1, days)).flatMap { offset -> [DoseOccurrence] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { return [] }
            return summary(for: day, calendar: calendar).occurrences
        }
        .filter { $0.record == nil && $0.scheduledTime > date }
        .sorted { $0.scheduledTime < $1.scheduledTime }
    }

    func overdueOccurrences(at date: Date = .now, calendar: Calendar = .current) -> [DoseOccurrence] {
        summary(for: date, calendar: calendar).occurrences.filter {
            if case .overdue = $0.status(at: date) { return true }
            return false
        }
    }

    func confirm(_ occurrence: DoseOccurrence, at actionTime: Date = .now) {
        doseRecords[occurrence.id] = MedicationDoseRecord(
            id: occurrence.id,
            planID: occurrence.plan.id,
            medicationID: occurrence.medication.id,
            scheduledTime: occurrence.scheduledTime,
            actionTime: actionTime,
            status: .taken,
            source: .scheduled
        )
        trimAndPersistRecords(referenceDate: actionTime)
    }

    func skip(_ occurrence: DoseOccurrence, at actionTime: Date = .now) {
        doseRecords[occurrence.id] = MedicationDoseRecord(
            id: occurrence.id,
            planID: occurrence.plan.id,
            medicationID: occurrence.medication.id,
            scheduledTime: occurrence.scheduledTime,
            actionTime: actionTime,
            status: .skipped,
            source: .scheduled
        )
        trimAndPersistRecords(referenceDate: actionTime)
    }

    @discardableResult
    func recordAsNeeded(planID: UUID, at actionTime: Date = .now) -> MedicationDoseRecord? {
        guard let plan = plan(id: planID),
              plan.kind == .asNeeded,
              plan.isEnabled,
              medication(id: plan.medicationID) != nil else { return nil }
        let record = MedicationDoseRecord(
            id: "prn.\(UUID().uuidString)",
            planID: plan.id,
            medicationID: plan.medicationID,
            scheduledTime: nil,
            actionTime: actionTime,
            status: .taken,
            source: .asNeeded
        )
        doseRecords[record.id] = record
        trimAndPersistRecords(referenceDate: actionTime)
        return record
    }

    func removeRecord(id: String) {
        doseRecords.removeValue(forKey: id)
        persist(doseRecords, key: doseRecordsKey)
    }

    private func migrateV1IfNeeded(calendar: Calendar, now: Date) {
        guard !defaults.bool(forKey: migrationKey) else { return }
        defer { defaults.set(true, forKey: migrationKey) }

        let hasLegacyData = defaults.data(forKey: settingsKeyV1) != nil || defaults.data(forKey: recordsKeyV1) != nil
        guard hasLegacyData else { return }
        let legacyRecords = Self.decode([String: DailyRecord].self, key: recordsKeyV1, defaults: defaults, decoder: decoder) ?? [:]
        let earliestDay = legacyRecords.values.map(\.day).min() ?? calendar.startOfDay(for: now)
        var migratedPlans: [DoseType: MedicationPlan] = [:]

        for dose in DoseType.allCases {
            let medication = Medication(name: dose.displayName, notes: "由 MediCheck 1.0 自动迁移")
            let plan = MedicationPlan(
                medicationID: medication.id,
                kind: .ongoing,
                startDate: earliestDay,
                reminderMinutes: [settings.minutes(for: dose)]
            )
            medications.append(medication)
            plans.append(plan)
            migratedPlans[dose] = plan
        }

        for legacyRecord in legacyRecords.values {
            for dose in DoseType.allCases {
                guard let entry = legacyRecord.entries[dose],
                      let confirmedTime = entry.confirmedTime,
                      let plan = migratedPlans[dose] else { continue }
                let occurrenceID = DateSupport.occurrenceID(
                    planID: plan.id,
                    day: legacyRecord.day,
                    minutes: settings.minutes(for: dose),
                    calendar: calendar
                )
                doseRecords[occurrenceID] = MedicationDoseRecord(
                    id: occurrenceID,
                    planID: plan.id,
                    medicationID: plan.medicationID,
                    scheduledTime: entry.scheduledTime,
                    actionTime: confirmedTime,
                    status: .taken,
                    source: .scheduled
                )
            }
        }
        persistV2()
    }

    private func trimAndPersistRecords(referenceDate: Date, calendar: Calendar = .current) {
        let cutoff = calendar.date(byAdding: .day, value: -730, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
        doseRecords = doseRecords.filter { _, record in record.actionTime >= cutoff }
        persist(doseRecords, key: doseRecordsKey)
    }

    private func normalizeScheduledRecordIDs(calendar: Calendar) {
        var normalized = doseRecords
        var changed = false

        for (storedKey, originalRecord) in doseRecords {
            guard originalRecord.source == .scheduled,
                  let scheduledTime = originalRecord.scheduledTime else { continue }
            let minutes = DateSupport.minutesSinceMidnight(for: scheduledTime, calendar: calendar)
            let canonicalID = DateSupport.occurrenceID(
                planID: originalRecord.planID,
                day: scheduledTime,
                minutes: minutes,
                calendar: calendar
            )
            guard storedKey != canonicalID || originalRecord.id != canonicalID else { continue }

            var record = originalRecord
            record.id = canonicalID
            normalized.removeValue(forKey: storedKey)
            if let existing = normalized[canonicalID] {
                normalized[canonicalID] = existing.actionTime >= record.actionTime ? existing : record
            } else {
                normalized[canonicalID] = record
            }
            changed = true
        }

        if changed {
            doseRecords = normalized
            persist(doseRecords, key: doseRecordsKey)
        }
    }

    private func persistV2() {
        persist(medications, key: medicationsKey)
        persist(plans, key: plansKey)
        persist(doseRecords, key: doseRecordsKey)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? encoder.encode(value) { defaults.set(data, forKey: key) }
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        key: String,
        defaults: UserDefaults,
        decoder: JSONDecoder
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
