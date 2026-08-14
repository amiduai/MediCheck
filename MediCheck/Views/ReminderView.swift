import SwiftUI

struct ReminderView: View {
    @ObservedObject var service: ReminderService
    @ObservedObject var storage: StorageService
    @State private var confirmingDose: DoseType?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 34))
                .foregroundStyle(iconColor)

            switch service.presentedContent {
            case .dose(let dose): doseReminder(dose)
            case .dailyStatus: dailyStatus
            case .eveningReview: eveningReview
            }
        }
        .padding(24)
        .frame(width: 360)
        .frame(minHeight: 260)
        .alert("确认已经服药？", isPresented: confirmationPresented, presenting: confirmingDose) { dose in
            Button("取消", role: .cancel) { confirmingDose = nil }
            Button("确认已经服药") {
                service.confirm(dose)
                confirmingDose = nil
            }
        } message: { _ in
            Text("请只在药已经真正服下后确认。")
        }
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(
            get: { confirmingDose != nil },
            set: { if !$0 { confirmingDose = nil } }
        )
    }

    private var iconName: String {
        service.presentedContent == .eveningReview ? "checklist" : "pill.fill"
    }

    private var iconColor: Color {
        service.presentedContent == .eveningReview ? .orange : .blue
    }

    @ViewBuilder
    private func doseReminder(_ dose: DoseType) -> some View {
        Text("该吃\(dose.displayName)了")
            .font(.title2.bold())
        Text("今天的\(dose.displayName)还没有确认。")
            .foregroundStyle(.secondary)

        Button("我已经吃了") { confirmingDose = dose }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        Button("\(storage.settings.repeatIntervalMinutes) 分钟后提醒") {
            service.snooze(dose)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private var dailyStatus: some View {
        VStack(spacing: 14) {
            Text("今天吃药了吗？")
                .font(.title2.bold())
            statusRows
            Button("知道了") { service.dismissWindow() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var eveningReview: some View {
        VStack(spacing: 14) {
            Text("今天还有服药记录未确认")
                .font(.headline)
            statusRows
            Text("请检查今天的服药记录。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("知道了") { service.dismissWindow() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var statusRows: some View {
        let record = storage.record(for: service.now)
        return VStack(spacing: 7) {
            ForEach(DoseType.allCases) { dose in
                if let entry = record.entries[dose] {
                    DoseStatusRow(dose: dose, entry: entry, now: service.now, compact: true)
                }
            }
        }
        .frame(maxWidth: 240)
    }
}
