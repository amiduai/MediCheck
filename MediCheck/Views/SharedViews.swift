import SwiftUI

struct MedicationOccurrenceRow: View {
    let occurrence: DoseOccurrence
    let now: Date
    var compact = false
    var onConfirm: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(occurrence.scheduledTime.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: compact ? 12 : 13, weight: .semibold, design: .rounded))
                Image(systemName: occurrence.medication.route.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: compact ? 50 : 58)

            VStack(alignment: .leading, spacing: 2) {
                Text(occurrence.medication.name)
                    .font(.system(size: compact ? 13 : 14, weight: .medium))
                    .lineLimit(1)
                if !occurrence.medication.detailLine.isEmpty {
                    Text(occurrence.medication.detailLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
            statusView
        }
        .padding(.vertical, compact ? 3 : 5)
    }

    @ViewBuilder
    private var statusView: some View {
        switch occurrence.status(at: now) {
        case .taken(let time):
            Label(time.formatted(date: .omitted, time: .shortened), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .skipped:
            Label("已跳过", systemImage: "minus.circle.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
        case .overdue:
            if let onConfirm {
                Button("确认", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Label("未确认", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        case .pending(let time):
            if let onConfirm {
                Button("提前确认", action: onConfirm)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Text("\(time.formatted(date: .omitted, time: .shortened)) 待用")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }
}

struct PlanKindBadge: View {
    let kind: MedicationPlanKind

    var body: some View {
        Text(kind.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch kind {
        case .fixedCourse: .blue
        case .ongoing: .purple
        case .asNeeded: .orange
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
