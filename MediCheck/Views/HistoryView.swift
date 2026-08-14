import SwiftUI

enum MonthCalendar {
    static func startOfMonth(containing date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    static func gridDays(for month: Date, calendar: Calendar = .current) -> [Date?] {
        let start = startOfMonth(containing: month, calendar: calendar)
        guard let dayRange = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let leadingEmptyDays = max(0, calendar.component(.weekday, from: start) - 1)
        var result: [Date?] = Array(repeating: nil, count: leadingEmptyDays)
        result.append(contentsOf: dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: start)
        }.map(Optional.some))
        while !result.count.isMultiple(of: 7) { result.append(nil) }
        return result
    }
}

struct HistoryView: View {
    @ObservedObject var storage: StorageService
    @State private var displayedMonth = MonthCalendar.startOfMonth(containing: .now)
    @State private var selectedDay = Date.now

    private let calendar = Calendar.current
    private let weekdays = ["日", "一", "二", "三", "四", "五", "六"]

    private var recentRecords: [DailyRecord] { storage.recentRecords(days: 7) }
    private var lastSevenCompleted: Int { recentRecords.reduce(0) { $0 + $1.completedCount } }
    private var selectedRecord: DailyRecord { storage.recordSnapshot(for: selectedDay) }
    private var today: Date { calendar.startOfDay(for: .now) }
    private var earliestMonth: Date {
        let cutoff = calendar.date(byAdding: .day, value: -89, to: today) ?? today
        return MonthCalendar.startOfMonth(containing: cutoff, calendar: calendar)
    }
    private var currentMonth: Date { MonthCalendar.startOfMonth(containing: today, calendar: calendar) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summary
                calendarCard
                selectedDayDetail
            }
            .padding(24)
        }
        .frame(minWidth: 500, minHeight: 650)
        .navigationTitle("服药记录")
    }

    private var summary: some View {
        SectionCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("最近 7 天")
                        .font(.headline)
                    Text("完成 \(lastSevenCompleted) / 21")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var calendarCard: some View {
        VStack(spacing: 14) {
            HStack {
                Button { moveMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .disabled(displayedMonth <= earliestMonth)

                Spacer()
                Text(displayedMonth.formatted(.dateTime.year().month(.wide)))
                    .font(.headline)
                Spacer()

                Button { moveMonth(by: 1) } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .disabled(displayedMonth >= currentMonth)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 7) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(MonthCalendar.gridDays(for: displayedMonth).enumerated()), id: \.offset) { _, day in
                    if let day {
                        calendarDay(day)
                    } else {
                        Color.clear.frame(height: 52)
                    }
                }
            }

            HStack(spacing: 14) {
                legend(color: .green, text: "3/3")
                legend(color: .orange, text: "部分确认")
                legend(color: .secondary, text: "未确认")
                Spacer()
            }
            .font(.caption)
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func calendarDay(_ day: Date) -> some View {
        let isFuture = day > today
        let record = storage.recordSnapshot(for: day)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)

        return Button {
            guard !isFuture else { return }
            selectedDay = day
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 13, weight: isToday ? .bold : .regular))
                if !isFuture {
                    Text("\(record.completedCount)/3")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(completionColor(record.completedCount))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(isFuture ? .tertiary : .primary)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel("\(day.formatted(date: .long, time: .omitted))，完成 \(record.completedCount) / 3")
    }

    private var selectedDayDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedDay.formatted(.dateTime.month().day().weekday(.wide)))
                    .font(.headline)
                if calendar.isDateInToday(selectedDay) {
                    Text("今天")
                        .font(.caption)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Text("\(selectedRecord.completedCount) / 3")
                    .fontWeight(.semibold)
            }

            Divider()

            ForEach(DoseType.allCases) { dose in
                HStack {
                    Text(dose.displayName)
                    Spacer()
                    if let confirmed = selectedRecord.entries[dose]?.confirmedTime {
                        Label(confirmed.formatted(date: .omitted, time: .shortened), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if calendar.isDateInToday(selectedDay),
                              let entry = selectedRecord.entries[dose],
                              entry.scheduledTime > .now {
                        Text("\(entry.scheduledTime.formatted(date: .omitted, time: .shortened)) 待服")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("未确认", systemImage: "circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func moveMonth(by offset: Int) {
        guard let month = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        displayedMonth = month
        if offset < 0 {
            let range = calendar.range(of: .day, in: .month, for: month)
            let lastDay = range?.count ?? 1
            selectedDay = calendar.date(byAdding: .day, value: lastDay - 1, to: month) ?? month
        } else {
            selectedDay = calendar.isDate(month, equalTo: today, toGranularity: .month) ? today : month
        }
    }

    private func completionColor(_ count: Int) -> Color {
        switch count {
        case 3: .green
        case 1...2: .orange
        default: .secondary
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).foregroundStyle(.secondary)
        }
    }
}
