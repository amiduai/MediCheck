import SwiftUI

struct MenuBarView: View {
    @ObservedObject var service: ReminderService
    @ObservedObject var storage: StorageService
    @Environment(\.openWindow) private var openWindow
    @State private var pendingScheduled: DoseOccurrence?
    @State private var pendingAsNeeded: MedicationPlan?

    private var today: DailyMedicationSummary { storage.summary(for: service.now) }
    private var asNeededPlans: [(medication: Medication, plan: MedicationPlan)] {
        storage.activeMedicationPlans.filter { $0.plan.kind == .asNeeded && $0.plan.isEnabled }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if today.occurrences.isEmpty && asNeededPlans.isEmpty {
                emptyState
            } else {
                scheduledSection
                if !asNeededPlans.isEmpty { asNeededSection }
            }

            Divider()
            progress
            navigationButtons

            Divider()
            Button("退出 MediCheck") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 340)
        .alert("确认已经用药？", isPresented: scheduledConfirmationPresented) {
            Button("取消", role: .cancel) { pendingScheduled = nil }
            Button("确认已经用药") {
                if let occurrence = pendingScheduled { service.confirm(occurrenceID: occurrence.id) }
                pendingScheduled = nil
            }
        } message: {
            Text(pendingScheduled.map { "\($0.medication.name) · \($0.medication.detailLine)\n请只在实际完成后确认。" } ?? "请只在实际完成后确认。")
        }
        .alert("记录一次按需用药？", isPresented: asNeededConfirmationPresented) {
            Button("取消", role: .cancel) { pendingAsNeeded = nil }
            Button("确认并记录") {
                if let plan = pendingAsNeeded { service.recordAsNeeded(planID: plan.id) }
                pendingAsNeeded = nil
            }
        } message: {
            let name = pendingAsNeeded.flatMap { storage.medication(id: $0.medicationID)?.name } ?? "该药品"
            Text("将记录现在使用了\(name)。")
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "pill.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("MediCheck")
                    .font(.headline)
                Text(service.now.formatted(.dateTime.month().day().weekday(.wide)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("v2")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.plus")
                .font(.title2)
                .foregroundStyle(.blue)
            Text("还没有用药计划")
                .font(.subheadline.weight(.medium))
            Text("添加固定疗程、长期计划或按需用药。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("添加用药计划") { openPlans() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var scheduledSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("今日计划")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if today.occurrences.isEmpty {
                Text("今天没有计划用药")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(today.occurrences) { occurrence in
                    MedicationOccurrenceRow(
                        occurrence: occurrence,
                        now: service.now,
                        compact: true,
                        onConfirm: isActionable(occurrence) ? { pendingScheduled = occurrence } : nil
                    )
                    if occurrence.id != today.occurrences.last?.id { Divider() }
                }
            }
        }
    }

    private var asNeededSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("按需用药")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(asNeededPlans, id: \.plan.id) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.medication.name).font(.subheadline.weight(.medium))
                        if !item.medication.detailLine.isEmpty {
                            Text(item.medication.detailLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("记录") { pendingAsNeeded = item.plan }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(.top, 4)
    }

    private var progress: some View {
        HStack {
            Text("今日已处理")
            Spacer()
            Text("\(today.resolvedCount) / \(today.scheduledCount)")
                .fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    private var navigationButtons: some View {
        VStack(spacing: 8) {
            Button(action: openPlans) {
                Label("管理用药", systemImage: "list.bullet.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            HStack {
                Button {
                    openWindow(id: "history")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("记录", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                SettingsLink {
                    Label("设置", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var scheduledConfirmationPresented: Binding<Bool> {
        Binding(get: { pendingScheduled != nil }, set: { if !$0 { pendingScheduled = nil } })
    }

    private var asNeededConfirmationPresented: Binding<Bool> {
        Binding(get: { pendingAsNeeded != nil }, set: { if !$0 { pendingAsNeeded = nil } })
    }

    private func isActionable(_ occurrence: DoseOccurrence) -> Bool {
        switch occurrence.status(at: service.now) {
        case .pending, .overdue: true
        case .taken, .skipped: false
        }
    }

    private func openPlans() {
        openWindow(id: "medication-plans")
        NSApp.activate(ignoringOtherApps: true)
    }
}
