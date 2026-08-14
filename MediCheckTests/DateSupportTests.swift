import XCTest
@testable import MediCheck

final class DateSupportTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    func testDefaultTimes() {
        XCTAssertEqual(MedicationSettings.defaults.minutes(for: .morning), 8 * 60 + 30)
        XCTAssertEqual(MedicationSettings.defaults.minutes(for: .noon), 12 * 60)
        XCTAssertEqual(MedicationSettings.defaults.minutes(for: .evening), 19 * 60)
        XCTAssertEqual(MedicationSettings.defaults.eveningCheckMinutes, 22 * 60 + 30)
    }

    func testStatusesRemainIndependent() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 13))!
        let morning = DoseEntry(doseType: .morning, scheduledTime: DateSupport.time(on: now, minutes: 8 * 60 + 30, calendar: calendar))
        let noon = DoseEntry(doseType: .noon, scheduledTime: DateSupport.time(on: now, minutes: 12 * 60, calendar: calendar))
        let evening = DoseEntry(doseType: .evening, scheduledTime: DateSupport.time(on: now, minutes: 19 * 60, calendar: calendar))

        XCTAssertEqual(DateSupport.status(entry: morning, now: now), .overdue)
        XCTAssertEqual(DateSupport.status(entry: noon, now: now), .overdue)
        XCTAssertEqual(DateSupport.status(entry: evening, now: now), .pending(evening.scheduledTime))
    }

    func testConfirmationWinsOverTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let confirmed = now.addingTimeInterval(-120)
        let entry = DoseEntry(doseType: .morning, scheduledTime: now.addingTimeInterval(-3600), confirmedTime: confirmed)
        XCTAssertEqual(DateSupport.status(entry: entry, now: now), .done(confirmed))
    }

    func testDayKeyUsesCalendarTimeZone() {
        let date = Date(timeIntervalSince1970: 1_786_641_600)
        XCTAssertEqual(DateSupport.dayKey(for: date, calendar: calendar).count, 10)
    }

    func testMonthCalendarGridStartsOnCorrectWeekday() {
        let august = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14))!
        let days = MonthCalendar.gridDays(for: august, calendar: calendar)
        XCTAssertTrue(days.count.isMultiple(of: 7))
        XCTAssertEqual(days.compactMap { $0 }.count, 31)
        XCTAssertEqual(days.prefix(6).compactMap { $0 }.count, 0)
        XCTAssertEqual(calendar.component(.day, from: days[6]!), 1)
    }

    @MainActor
    func testConfirmationPersistsAndDoesNotCompleteOtherDoses() {
        let suiteName = "MediCheckTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 13))!

        let storage = StorageService(defaults: defaults)
        storage.confirm(.morning, at: date, calendar: calendar)

        let reloaded = StorageService(defaults: defaults)
        let record = reloaded.record(for: date, calendar: calendar)
        XCTAssertEqual(record.completedCount, 1)
        XCTAssertEqual(record.entries[.morning]?.confirmedTime, date)
        XCTAssertNil(record.entries[.noon]?.confirmedTime)
        XCTAssertNil(record.entries[.evening]?.confirmedTime)
    }
}
