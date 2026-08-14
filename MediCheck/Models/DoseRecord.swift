import Foundation

struct DoseEntry: Codable, Equatable {
    let doseType: DoseType
    var scheduledTime: Date
    var confirmedTime: Date?
}

struct DailyRecord: Codable, Identifiable, Equatable {
    let id: String
    var day: Date
    var entries: [DoseType: DoseEntry]

    var completedCount: Int {
        entries.values.filter { $0.confirmedTime != nil }.count
    }
}

