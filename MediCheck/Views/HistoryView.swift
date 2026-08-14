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

    private var selectedSummary: DailyMedicationSummary { storage.summary(for: selectedDay) }
    private var today: Date { calendar.startOfDay(for: .now) }
    private var currentMonth: Date { MonthCalendar.startOfMonth(containing: today, calendar: calendar) }
    private var earliestMonth: Date {
        let recordDates = storage.doseRecords.values.map(\.actionTime)
        let planDates = storage.plans.map(\.startDate)
        let earliest = (recordDates + planDates).min() ?? today
        let cutoff = calendar.date(byAdding: .day, value: -729, to: today) ?? today
        return MonthCalendar.startOfMonth(containing: max(earliest, cutoff), calendar: calendar)
    }
    private var lastSevenSummaries: [DailyMedicationSummary] {
        (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return storage.summary(for: day)
        }
    }
    private var recentCompleted: Int { lastSevenSummaries.reduce(0) { $0 + $1.completedCount } }
    private var recentScheduled: Int { lastSevenSummaries.reduce(0) { $0 + $1.scheduledCount } }
    private var recentAsNeeded: Int { lastSevenSummaries.reduce(0) { $0 + $1.asNeededRecords.count } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard
                calendarCard
                selectedDayDetail
            }
            .padding(24)
        }
        .frame(minWidth: 540, minHeight: 650)
        .navigationTitle("用药记录")
    }

    private var summaryCard: some View {
        SectionCard {
            HStack(spacing: 28) {
                metric(title: "最近 7 天", value: "\(recentCompleted) / \(recentScheduled)", detail: "计划已确认")
                Divider().frame(height: 42)
                metric(title: "按需记录", value: "\(recentAsNeeded)", detail: "次实际使用")
                Spacer()
            }
        }
    }

    private func metric(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var calendarCard: some View {
        VStack(spacing: 14) {
            HStack {
                Button { moveMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .disabled(displayedMonth <= earliestMonth)
                Spacer()
                Text(displayedMonth.formatted(.dateTime.year().month(.wide)))
                    .font(.headline)
                Spacer()
                Button { moveMonth(by: 1) } label: { Image(systemName: "chevron.right") }
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
                    if let day { calendarDay(day) } else { Color.clear.frame(height: 52) }
                }
            }

            HStack(spacing: 14) {
                legend(color: .green, text: "全部确认")
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
        let summary = storage.summary(for: day)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)

        return Button {
            guard !isFuture else { return }
            selectedDay = day
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 13, weight: isToday ? .bold : .regular))
                if !isFuture && (summary.scheduledCount > 0 || !summary.asNeededRecords.isEmpty) {
                    Text(summary.scheduledCount > 0 ? "\(summary.completedCount)/\(summary.scheduledCount)" : "+\(summary.asNeededRecords.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(completionColor(summary))
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
        .accessibilityLabel("\(day.formatted(date: .long, time: .omitted))，完成 \(summary.completedCount) / \(summary.scheduledCount)")
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
                Text("\(selectedSummary.completedCount) / \(selectedSummary.scheduledCount)")
                    .fontWeight(.semibold)
            }

            Divider()

            if selectedSummary.occurrences.isEmpty && selectedSummary.asNeededRecords.isEmpty {
                Text("这一天没有用药计划或记录")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                ForEach(selectedSummary.occurrences) { occurrence in
                    MedicationOccurrenceRow(occurrence: occurrence, now: calendar.isDateInToday(selectedDay) ? .now : .distantFuture)
                    if occurrence.id != selectedSummary.occurrences.last?.id { Divider() }
                }
                if !selectedSummary.asNeededRecords.isEmpty {
                    if !selectedSummary.occurrences.isEmpty { Divider() }
                    Text("按需记录")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(selectedSummary.asNeededRecords) { record in
                        HStack {
                            Label(storage.medication(id: record.medicationID)?.name ?? "已删除的药品", systemImage: "clock.badge.checkmark")
                            Spacer()
                            Text(record.actionTime.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
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
            selectedDay = calendar.date(byAdding: .day, value: (range?.count ?? 1) - 1, to: month) ?? month
        } else {
            selectedDay = calendar.isDate(month, equalTo: today, toGranularity: .month) ? today : month
        }
    }

    private func completionColor(_ summary: DailyMedicationSummary) -> Color {
        if summary.scheduledCount == 0 { return .blue }
        if summary.completedCount == summary.scheduledCount { return .green }
        if summary.completedCount > 0 { return .orange }
        return .secondary
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).foregroundStyle(.secondary)
        }
    }
}
