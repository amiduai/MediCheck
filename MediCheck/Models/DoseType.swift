import Foundation

enum DoseType: String, Codable, CaseIterable, Identifiable, Sendable {
    case morning
    case noon
    case evening

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .morning: "早药"
        case .noon: "中药"
        case .evening: "晚药"
        }
    }

    var shortName: String {
        switch self {
        case .morning: "早"
        case .noon: "中"
        case .evening: "晚"
        }
    }

    var defaultMinutes: Int {
        switch self {
        case .morning: 8 * 60 + 30
        case .noon: 12 * 60
        case .evening: 19 * 60
        }
    }
}

enum DoseStatus: Equatable {
    case pending(Date)
    case overdue
    case done(Date)
}

