import Foundation

enum DateSupport {
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func time(on day: Date, minutes: Int, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
    }

    static func minutesSinceMidnight(for date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func occurrenceID(planID: UUID, day: Date, minutes: Int, calendar: Calendar = .current) -> String {
        "\(planID.uuidString).\(dayKey(for: day, calendar: calendar)).minute\(minutes)"
    }

    static func status(entry: DoseEntry, now: Date) -> DoseStatus {
        if let confirmed = entry.confirmedTime {
            return .done(confirmed)
        }
        return now >= entry.scheduledTime ? .overdue : .pending(entry.scheduledTime)
    }
}
