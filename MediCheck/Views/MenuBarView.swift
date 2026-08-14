import SwiftUI

struct MenuBarView: View {
    @ObservedObject var service: ReminderService
    @ObservedObject var storage: StorageService
    @Environment(\.openWindow) private var openWindow

    private var today: DailyRecord { storage.record(for: service.now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "pill.fill")
                    .foregroundStyle(.blue)
                Text("吃药提醒")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("今天")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(service.now.formatted(.dateTime.month().day().weekday(.wide)))
                    .font(.subheadline.weight(.medium))
            }

            VStack(spacing: 10) {
                ForEach(DoseType.allCases) { dose in
                    if let entry = today.entries[dose] {
                        DoseStatusRow(dose: dose, entry: entry, now: service.now, compact: true)
                    }
                }
            }

            Divider()

            HStack {
                Text("今日完成")
                Spacer()
                Text("\(today.completedCount) / \(DoseType.allCases.count)")
                    .fontWeight(.semibold)
            }
            .font(.subheadline)

            Button {
                openWindow(id: "history")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("查看记录", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            SettingsLink {
                Label("设置", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            Divider()
            Button("退出 MediCheck") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 280)
    }
}
