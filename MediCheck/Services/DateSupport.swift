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

    static func status(entry: DoseEntry, now: Date) -> DoseStatus {
        if let confirmed = entry.confirmedTime {
            return .done(confirmed)
        }
        return now >= entry.scheduledTime ? .overdue : .pending(entry.scheduledTime)
    }
}

