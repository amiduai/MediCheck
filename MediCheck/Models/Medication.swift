import Foundation

enum MedicationRoute: String, Codable, CaseIterable, Identifiable, Sendable {
    case oral
    case nasal
    case inhaled
    case topical
    case injection
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oral: "口服"
        case .nasal: "喷鼻"
        case .inhaled: "吸入"
        case .topical: "外用"
        case .injection: "注射"
        case .other: "其他"
        }
    }

    var systemImage: String {
        switch self {
        case .oral: "pill.fill"
        case .nasal: "nose.fill"
        case .inhaled: "lungs.fill"
        case .topical: "drop.fill"
        case .injection: "syringe.fill"
        case .other: "cross.case.fill"
        }
    }
}

enum MedicationPlanKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case fixedCourse
    case ongoing
    case asNeeded

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fixedCourse: "固定疗程"
        case .ongoing: "长期计划"
        case .asNeeded: "按需用药"
        }
    }
}

struct Medication: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var strength: String
    var doseAmount: String
    var form: String
    var route: MedicationRoute
    var notes: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        strength: String = "",
        doseAmount: String = "",
        form: String = "",
        route: MedicationRoute = .oral,
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.strength = strength
        self.doseAmount = doseAmount
        self.form = form
        self.route = route
        self.notes = notes
        self.createdAt = createdAt
    }

    var detailLine: String {
        [strength, doseAmount, form, route.displayName]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " · ")
    }
}

struct MedicationPlan: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var medicationID: UUID
    var kind: MedicationPlanKind
    var startDate: Date
    var endDate: Date?
    var reminderMinutes: [Int]
    var weekdays: [Int]
    var isEnabled: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        medicationID: UUID,
        kind: MedicationPlanKind,
        startDate: Date,
        endDate: Date? = nil,
        reminderMinutes: [Int] = [],
        weekdays: [Int] = Array(1...7),
        isEnabled: Bool = true,
        createdAt: Date = .now
    ) {
        self.id = id
        self.medicationID = medicationID
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.reminderMinutes = Array(Set(reminderMinutes)).sorted()
        self.weekdays = Array(Set(weekdays.filter { (1...7).contains($0) })).sorted()
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    func isScheduled(on date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled, kind != .asNeeded else { return false }
        let day = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: startDate)
        guard day >= start else { return false }
        if kind == .fixedCourse {
            guard let endDate, day <= calendar.startOfDay(for: endDate) else { return false }
        }
        return weekdays.contains(calendar.component(.weekday, from: day))
    }

    var scheduleDescription: String {
        if kind == .asNeeded { return "不定时提醒，仅记录实际使用" }
        let frequency = reminderMinutes.isEmpty ? "未设置时间" : "每日 \(reminderMinutes.count) 次"
        if kind == .fixedCourse, let endDate {
            return "\(frequency) · \(startDate.formatted(date: .numeric, time: .omitted))–\(endDate.formatted(date: .numeric, time: .omitted))"
        }
        return frequency
    }
}

enum DoseRecordStatus: String, Codable, Sendable {
    case taken
    case skipped
}

enum DoseRecordSource: String, Codable, Sendable {
    case scheduled
    case asNeeded
}

struct MedicationDoseRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var planID: UUID
    var medicationID: UUID
    var scheduledTime: Date?
    var actionTime: Date
    var status: DoseRecordStatus
    var source: DoseRecordSource
}

enum DoseOccurrenceStatus: Equatable, Sendable {
    case pending(Date)
    case overdue
    case taken(Date)
    case skipped(Date)
}

struct DoseOccurrence: Identifiable, Equatable, Sendable {
    let id: String
    let slotIndex: Int
    let medication: Medication
    let plan: MedicationPlan
    let scheduledTime: Date
    let record: MedicationDoseRecord?

    func status(at now: Date) -> DoseOccurrenceStatus {
        if let record {
            switch record.status {
            case .taken: return .taken(record.actionTime)
            case .skipped: return .skipped(record.actionTime)
            }
        }
        return now >= scheduledTime ? .overdue : .pending(scheduledTime)
    }
}

struct DailyMedicationSummary: Equatable, Sendable {
    let day: Date
    let occurrences: [DoseOccurrence]
    let asNeededRecords: [MedicationDoseRecord]

    var scheduledCount: Int { occurrences.count }
    var resolvedCount: Int { occurrences.filter { $0.record != nil }.count }
    var completedCount: Int {
        occurrences.filter { $0.record?.status == .taken }.count
    }
}
