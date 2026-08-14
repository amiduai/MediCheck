import XCTest
@testable import MediCheck

final class DateSupportTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    func testDefaultReminderSettings() {
        XCTAssertTrue(MedicationSettings.defaults.notificationsEnabled)
        XCTAssertTrue(MedicationSettings.defaults.repeatRemindersEnabled)
        XCTAssertEqual(MedicationSettings.defaults.repeatIntervalMinutes, 10)
        XCTAssertEqual(MedicationSettings.defaults.eveningCheckMinutes, 22 * 60 + 30)
    }

    func testFixedCourseIncludesStartAndEndOnly() {
        let start = date(day: 14)
        let end = date(day: 27)
        let plan = MedicationPlan(
            medicationID: UUID(),
            kind: .fixedCourse,
            startDate: start,
            endDate: end,
            reminderMinutes: [8 * 60, 20 * 60]
        )

        XCTAssertFalse(plan.isScheduled(on: date(day: 13), calendar: calendar))
        XCTAssertTrue(plan.isScheduled(on: start, calendar: calendar))
        XCTAssertTrue(plan.isScheduled(on: end, calendar: calendar))
        XCTAssertFalse(plan.isScheduled(on: date(day: 28), calendar: calendar))
    }

    func testWeekdayFilterIsApplied() {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 17))!
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        let plan = MedicationPlan(
            medicationID: UUID(),
            kind: .ongoing,
            startDate: monday,
            reminderMinutes: [8 * 60],
            weekdays: [2]
        )

        XCTAssertTrue(plan.isScheduled(on: monday, calendar: calendar))
        XCTAssertFalse(plan.isScheduled(on: tuesday, calendar: calendar))
    }

    @MainActor
    func testNewInstallStartsWithoutMedicationPlans() {
        withDefaults { defaults in
            let storage = StorageService(defaults: defaults, calendar: calendar, now: date(day: 14))
            XCTAssertTrue(storage.medications.isEmpty)
            XCTAssertTrue(storage.plans.isEmpty)
            XCTAssertTrue(storage.doseRecords.isEmpty)
        }
    }

    @MainActor
    func testArbitraryPlansProduceIndependentOccurrencesAndPersistConfirmation() {
        withDefaults { defaults in
            let day = date(day: 14, hour: 12)
            let storage = StorageService(defaults: defaults, calendar: calendar, now: day)
            let first = Medication(name: "药品 A", strength: "10 mg", doseAmount: "1 片")
            let firstPlan = MedicationPlan(
                medicationID: first.id,
                kind: .ongoing,
                startDate: day,
                reminderMinutes: [8 * 60, 20 * 60]
            )
            let second = Medication(name: "药品 B", route: .nasal)
            let secondPlan = MedicationPlan(
                medicationID: second.id,
                kind: .ongoing,
                startDate: day,
                reminderMinutes: [9 * 60]
            )
            storage.saveMedication(first, plan: firstPlan)
            storage.saveMedication(second, plan: secondPlan)

            let summary = storage.summary(for: day, calendar: calendar)
            XCTAssertEqual(summary.scheduledCount, 3)
            XCTAssertEqual(summary.occurrences.map(\.medication.name), ["药品 A", "药品 B", "药品 A"])

            storage.confirm(summary.occurrences[0], at: day)
            let reloaded = StorageService(defaults: defaults, calendar: calendar, now: day)
            let persisted = reloaded.summary(for: day, calendar: calendar)
            XCTAssertEqual(persisted.completedCount, 1)
            XCTAssertEqual(persisted.occurrences.filter { $0.record == nil }.count, 2)
        }
    }

    @MainActor
    func testEditingTimesDoesNotMoveExistingConfirmationToAnotherSlot() {
        withDefaults { defaults in
            let day = date(day: 14, hour: 21)
            let storage = StorageService(defaults: defaults, calendar: calendar, now: day)
            let medication = Medication(name: "药品 A")
            var plan = MedicationPlan(
                medicationID: medication.id,
                kind: .ongoing,
                startDate: day,
                reminderMinutes: [8 * 60, 20 * 60]
            )
            storage.saveMedication(medication, plan: plan)
            let evening = storage.summary(for: day, calendar: calendar).occurrences[1]
            storage.confirm(evening, at: day)

            plan.reminderMinutes = [7 * 60, 8 * 60, 20 * 60]
            storage.saveMedication(medication, plan: plan)

            let summary = storage.summary(for: day, calendar: calendar)
            XCTAssertEqual(summary.scheduledCount, 3)
            XCTAssertEqual(summary.completedCount, 1)
            XCTAssertEqual(
                DateSupport.minutesSinceMidnight(for: summary.occurrences.first { $0.record != nil }!.scheduledTime, calendar: calendar),
                20 * 60
            )
        }
    }

    @MainActor
    func testAsNeededMedicationCreatesActualUseRecordOnly() {
        withDefaults { defaults in
            let now = date(day: 14, hour: 15)
            let storage = StorageService(defaults: defaults, calendar: calendar, now: now)
            let medication = Medication(name: "按需药品")
            let plan = MedicationPlan(
                medicationID: medication.id,
                kind: .asNeeded,
                startDate: now
            )
            storage.saveMedication(medication, plan: plan)

            XCTAssertTrue(storage.summary(for: now, calendar: calendar).occurrences.isEmpty)
            XCTAssertNotNil(storage.recordAsNeeded(planID: plan.id, at: now))
            XCTAssertEqual(storage.summary(for: now, calendar: calendar).asNeededRecords.count, 1)
        }
    }

    @MainActor
    func testV1DataMigratesToThreeGenericPlansAndKeepsConfirmation() throws {
        let suiteName = "MediCheckTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let day = date(day: 14)
        let confirmation = date(day: 14, hour: 9)
        let settings = MedicationSettings.defaults
        let entries = Dictionary(uniqueKeysWithValues: DoseType.allCases.map { dose in
            let scheduled = DateSupport.time(on: day, minutes: settings.minutes(for: dose), calendar: calendar)
            return (dose, DoseEntry(
                doseType: dose,
                scheduledTime: scheduled,
                confirmedTime: dose == .morning ? confirmation : nil
            ))
        })
        let record = DailyRecord(id: DateSupport.dayKey(for: day, calendar: calendar), day: day, entries: entries)
        defaults.set(try JSONEncoder().encode(settings), forKey: "medicheck.settings.v1")
        defaults.set(try JSONEncoder().encode([record.id: record]), forKey: "medicheck.records.v1")

        let storage = StorageService(defaults: defaults, calendar: calendar, now: day)

        XCTAssertEqual(storage.medications.count, 3)
        XCTAssertEqual(storage.plans.count, 3)
        XCTAssertEqual(storage.summary(for: day, calendar: calendar).scheduledCount, 3)
        XCTAssertEqual(storage.summary(for: day, calendar: calendar).completedCount, 1)
        XCTAssertNotNil(defaults.data(forKey: "medicheck.records.v1"))
    }

    @MainActor
    func testLegacyV2SlotIdentifierIsNormalizedWithoutDuplicateOccurrence() throws {
        let suiteName = "MediCheckTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let day = date(day: 14)
        let scheduled = date(day: 14, hour: 8)
        let medication = Medication(name: "药品 A")
        let plan = MedicationPlan(
            medicationID: medication.id,
            kind: .ongoing,
            startDate: day,
            reminderMinutes: [8 * 60]
        )
        let oldID = "\(plan.id.uuidString).\(DateSupport.dayKey(for: day, calendar: calendar)).slot0"
        let record = MedicationDoseRecord(
            id: oldID,
            planID: plan.id,
            medicationID: medication.id,
            scheduledTime: scheduled,
            actionTime: date(day: 14, hour: 9),
            status: .taken,
            source: .scheduled
        )
        let encoder = JSONEncoder()
        defaults.set(try encoder.encode([medication]), forKey: "medicheck.medications.v2")
        defaults.set(try encoder.encode([plan]), forKey: "medicheck.plans.v2")
        defaults.set(try encoder.encode([oldID: record]), forKey: "medicheck.doseRecords.v2")

        let storage = StorageService(defaults: defaults, calendar: calendar, now: day)
        let summary = storage.summary(for: day, calendar: calendar)

        XCTAssertEqual(summary.scheduledCount, 1)
        XCTAssertEqual(summary.completedCount, 1)
        XCTAssertEqual(storage.doseRecords.count, 1)
        XCTAssertTrue(storage.doseRecords.keys.first?.contains(".minute480") == true)
    }

    func testMonthCalendarGridStartsOnCorrectWeekday() {
        let august = date(day: 14)
        let days = MonthCalendar.gridDays(for: august, calendar: calendar)
        XCTAssertTrue(days.count.isMultiple(of: 7))
        XCTAssertEqual(days.compactMap { $0 }.count, 31)
        XCTAssertEqual(days.prefix(6).compactMap { $0 }.count, 0)
        XCTAssertEqual(calendar.component(.day, from: days[6]!), 1)
    }

    private func date(day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
    }

    @MainActor
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suiteName = "MediCheckTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}
