import SwiftUI

struct DoseStatusRow: View {
    let dose: DoseType
    let entry: DoseEntry
    let now: Date
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            Text(dose.shortName)
                .fontWeight(.medium)
                .frame(width: compact ? 24 : 36, alignment: .leading)
            Spacer()
            statusText
        }
        .font(.system(size: compact ? 13 : 14))
    }

    @ViewBuilder
    private var statusText: some View {
        switch DateSupport.status(entry: entry, now: now) {
        case .done(let time):
            Label(time.formatted(date: .omitted, time: .shortened), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .overdue:
            Label("尚未确认", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        case .pending(let time):
            Text("\(time.formatted(date: .omitted, time: .shortened)) 待服")
                .foregroundStyle(.secondary)
        }
    }
}

struct SectionCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 12) { content }
            .padding(16)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

