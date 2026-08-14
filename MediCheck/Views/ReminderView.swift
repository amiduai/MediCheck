import SwiftUI

struct ReminderView: View {
    @ObservedObject var service: ReminderService
    @ObservedObject var storage: StorageService
    @State private var confirmingOccurrenceID: String?
    @State private var skippingOccurrenceID: String?

    private var today: DailyMedicationSummary { storage.summary(for: service.now) }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 34))
                .foregroundStyle(iconColor)

            switch service.presentedContent {
            case .occurrence:
                occurrenceReminder
            case .dailyStatus:
                dailyStatus
            case .dailyReview:
                dailyReview
            }
        }
        .padding(24)
        .frame(width: 420)
        .frame(minHeight: 300)
        .alert("确认已经用药？", isPresented: confirmationPresented) {
            Button("取消", role: .cancel) { confirmingOccurrenceID = nil }
            Button("确认已经用药") {
                if let id = confirmingOccurrenceID { service.confirm(occurrenceID: id) }
                confirmingOccurrenceID = nil
            }
        } message: {
            Text("请只在本次用药已经实际完成后确认。")
        }
        .alert("跳过本次计划？", isPresented: skippingPresented) {
            Button("取消", role: .cancel) { skippingOccurrenceID = nil }
            Button("跳过", role: .destructive) {
                if let id = skippingOccurrenceID { service.skip(occurrenceID: id) }
                skippingOccurrenceID = nil
            }
        } message: {
            Text("这只会记录本次未用药，不会改变后续提醒。")
        }
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(get: { confirmingOccurrenceID != nil }, set: { if !$0 { confirmingOccurrenceID = nil } })
    }

    private var skippingPresented: Binding<Bool> {
        Binding(get: { skippingOccurrenceID != nil }, set: { if !$0 { skippingOccurrenceID = nil } })
    }

    private var iconName: String {
        service.presentedContent == .dailyReview ? "checklist" : "pill.fill"
    }

    private var iconColor: Color {
        service.presentedContent == .dailyReview ? .orange : .blue
    }

    @ViewBuilder
    private var occurrenceReminder: some View {
        if let occurrence = service.presentedOccurrence {
            VStack(spacing: 10) {
                Text("该用 \(occurrence.medication.name) 了")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                if !occurrence.medication.detailLine.isEmpty {
                    Text(occurrence.medication.detailLine)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Text("计划时间 \(occurrence.scheduledTime.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !occurrence.medication.notes.isEmpty {
                    Text(occurrence.medication.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                HStack(spacing: 10) {
                    Button("跳过本次") { skippingOccurrenceID = occurrence.id }
                        .buttonStyle(.bordered)
                    Button("我已经用了") { confirmingOccurrenceID = occurrence.id }
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)

                Button("\(storage.settings.repeatIntervalMinutes) 分钟后提醒") {
                    service.snooze(occurrenceID: occurrence.id)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        } else {
            Text("这条提醒已失效")
                .font(.headline)
            Button("关闭") { service.dismissWindow() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var dailyStatus: some View {
        VStack(spacing: 14) {
            Text("今天的用药计划")
                .font(.title2.bold())
            statusRows
            Button("知道了") { service.dismissWindow() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var dailyReview: some View {
        VStack(spacing: 14) {
            Text("今天还有计划未确认")
                .font(.headline)
            statusRows
            Text("请核对实际情况；不要根据提醒自行补服。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("知道了") { service.dismissWindow() }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var statusRows: some View {
        if today.occurrences.isEmpty {
            Text("今天没有定时计划")
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(today.occurrences) { occurrence in
                        MedicationOccurrenceRow(occurrence: occurrence, now: service.now, compact: true)
                        if occurrence.id != today.occurrences.last?.id { Divider() }
                    }
                }
            }
            .frame(maxHeight: 230)
        }
    }
}
