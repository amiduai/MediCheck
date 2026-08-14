import SwiftUI

private struct PlanDisplayItem: Identifiable {
    let medication: Medication
    let plan: MedicationPlan
    var id: UUID { plan.id }
}

struct MedicationPlansView: View {
    @ObservedObject var service: ReminderService
    @ObservedObject var storage: StorageService
    @State private var editorItem: PlanDisplayItem?
    @State private var isAdding = false
    @State private var pendingDeletion: PlanDisplayItem?
    @State private var pendingAsNeeded: PlanDisplayItem?

    private var items: [PlanDisplayItem] {
        storage.activeMedicationPlans.map { PlanDisplayItem(medication: $0.medication, plan: $0.plan) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("用药计划")
                        .font(.title2.bold())
                    Text("按医生或药师给出的方案录入，MediCheck 不判断剂量。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isAdding = true
                } label: {
                    Label("添加计划", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)

            Divider()

            if items.isEmpty {
                ContentUnavailableView {
                    Label("还没有用药计划", systemImage: "list.bullet.clipboard")
                } description: {
                    Text("可以添加固定疗程、长期计划或按需用药。")
                } actions: {
                    Button("添加第一个计划") { isAdding = true }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
                            planCard(item)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 520)
        .sheet(isPresented: $isAdding) {
            MedicationPlanEditor(service: service, storage: storage)
        }
        .sheet(item: $editorItem) { item in
            MedicationPlanEditor(
                service: service,
                storage: storage,
                medication: item.medication,
                plan: item.plan
            )
        }
        .alert("删除这个用药计划？", isPresented: deletionPresented) {
            Button("取消", role: .cancel) { pendingDeletion = nil }
            Button("删除", role: .destructive) {
                if let item = pendingDeletion {
                    storage.deleteMedication(item.medication.id)
                    service.dataDidChange()
                }
                pendingDeletion = nil
            }
        } message: {
            Text("计划和该药品的本地记录将被删除，此操作无法撤销。")
        }
        .alert("记录一次按需用药？", isPresented: asNeededPresented) {
            Button("取消", role: .cancel) { pendingAsNeeded = nil }
            Button("确认并记录") {
                if let item = pendingAsNeeded { service.recordAsNeeded(planID: item.plan.id) }
                pendingAsNeeded = nil
            }
        } message: {
            Text("只应在实际使用后记录。")
        }
    }

    private func planCard(_ item: PlanDisplayItem) -> some View {
        SectionCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: item.medication.route.systemImage)
                    .font(.title2)
                    .foregroundStyle(item.plan.isEnabled ? Color.accentColor : .secondary)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(item.plan.isEnabled ? 0.10 : 0), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(item.medication.name)
                            .font(.headline)
                        PlanKindBadge(kind: item.plan.kind)
                        if !item.plan.isEnabled {
                            Text("已停用")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !item.medication.detailLine.isEmpty {
                        Text(item.medication.detailLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(scheduleText(item.plan))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !item.medication.notes.isEmpty {
                        Text(item.medication.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    if item.plan.kind == .asNeeded && item.plan.isEnabled {
                        Button("记录一次") { pendingAsNeeded = item }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    Menu {
                        Button("编辑") { editorItem = item }
                        Button(item.plan.isEnabled ? "停用计划" : "启用计划") {
                            storage.setPlanEnabled(item.plan.id, enabled: !item.plan.isEnabled)
                            service.dataDidChange()
                        }
                        Divider()
                        Button("删除", role: .destructive) { pendingDeletion = item }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
        .opacity(item.plan.isEnabled ? 1 : 0.65)
    }

    private func scheduleText(_ plan: MedicationPlan) -> String {
        guard plan.kind != .asNeeded else { return "不定时提醒，仅记录实际使用" }
        let times = plan.reminderMinutes
            .map { DateSupport.time(on: .now, minutes: $0).formatted(date: .omitted, time: .shortened) }
            .joined(separator: "、")
        let dateRange: String
        if plan.kind == .fixedCourse, let endDate = plan.endDate {
            dateRange = " · \(plan.startDate.formatted(date: .abbreviated, time: .omitted))–\(endDate.formatted(date: .abbreviated, time: .omitted))"
        } else {
            dateRange = " · 从 \(plan.startDate.formatted(date: .abbreviated, time: .omitted)) 开始"
        }
        return "\(times)\(dateRange)"
    }

    private var deletionPresented: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }

    private var asNeededPresented: Binding<Bool> {
        Binding(get: { pendingAsNeeded != nil }, set: { if !$0 { pendingAsNeeded = nil } })
    }
}

private struct MedicationPlanEditor: View {
    @ObservedObject var service: ReminderService
    @ObservedObject var storage: StorageService
    @Environment(\.dismiss) private var dismiss

    private let medicationID: UUID
    private let planID: UUID
    private let createdAt: Date
    private let planCreatedAt: Date

    @State private var name: String
    @State private var strength: String
    @State private var doseAmount: String
    @State private var form: String
    @State private var route: MedicationRoute
    @State private var notes: String
    @State private var kind: MedicationPlanKind
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var weekdays: Set<Int>
    @State private var reminderTimes: [Date]
    @State private var isEnabled: Bool

    private let weekdayOptions = [
        (1, "日"), (2, "一"), (3, "二"), (4, "三"), (5, "四"), (6, "五"), (7, "六")
    ]

    init(
        service: ReminderService,
        storage: StorageService,
        medication: Medication? = nil,
        plan: MedicationPlan? = nil
    ) {
        self.service = service
        self.storage = storage
        let medication = medication ?? Medication(name: "")
        let plan = plan ?? MedicationPlan(
            medicationID: medication.id,
            kind: .ongoing,
            startDate: Calendar.current.startOfDay(for: .now),
            reminderMinutes: [8 * 60]
        )
        medicationID = medication.id
        planID = plan.id
        createdAt = medication.createdAt
        planCreatedAt = plan.createdAt
        _name = State(initialValue: medication.name)
        _strength = State(initialValue: medication.strength)
        _doseAmount = State(initialValue: medication.doseAmount)
        _form = State(initialValue: medication.form)
        _route = State(initialValue: medication.route)
        _notes = State(initialValue: medication.notes)
        _kind = State(initialValue: plan.kind)
        _startDate = State(initialValue: plan.startDate)
        _endDate = State(initialValue: plan.endDate ?? Calendar.current.date(byAdding: .day, value: 13, to: plan.startDate) ?? plan.startDate)
        _weekdays = State(initialValue: Set(plan.weekdays))
        _reminderTimes = State(initialValue: plan.reminderMinutes.map { DateSupport.time(on: .now, minutes: $0) })
        _isEnabled = State(initialValue: plan.isEnabled)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "添加用药计划" : "编辑用药计划")
                    .font(.title3.bold())
                Spacer()
                Button("取消") { dismiss() }
                Button("保存", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(20)

            Divider()

            Form {
                Section("药品信息") {
                    TextField("药品名称（必填）", text: $name)
                    HStack {
                        TextField("规格，例如 50 mg", text: $strength)
                        TextField("每次用量，例如 1 片", text: $doseAmount)
                    }
                    HStack {
                        TextField("剂型，例如 片剂", text: $form)
                        Picker("使用方式", selection: $route) {
                            ForEach(MedicationRoute.allCases) { route in
                                Text(route.displayName).tag(route)
                            }
                        }
                    }
                    TextField("备注（例如医生交代的注意事项）", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("计划类型") {
                    Picker("类型", selection: $kind) {
                        ForEach(MedicationPlanKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    if kind == .fixedCourse {
                        DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                        DatePicker("结束日期", selection: $endDate, in: startDate..., displayedComponents: .date)
                    } else if kind == .ongoing {
                        DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                    } else {
                        Text("按需用药不会定时提醒，只记录实际使用时间。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if kind != .asNeeded {
                    Section("提醒时间") {
                        ForEach(reminderTimes.indices, id: \.self) { index in
                            HStack {
                                DatePicker("第 \(index + 1) 次", selection: $reminderTimes[index], displayedComponents: .hourAndMinute)
                                Button(role: .destructive) {
                                    reminderTimes.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .disabled(reminderTimes.count == 1)
                            }
                        }
                        Button {
                            let last = reminderTimes.last ?? DateSupport.time(on: .now, minutes: 8 * 60)
                            reminderTimes.append(Calendar.current.date(byAdding: .hour, value: 4, to: last) ?? last)
                        } label: {
                            Label("添加时间", systemImage: "plus.circle")
                        }

                        HStack(spacing: 7) {
                            Text("每周")
                            ForEach(weekdayOptions, id: \.0) { value, label in
                                Button(label) { toggleWeekday(value) }
                                    .buttonStyle(.bordered)
                                    .tint(weekdays.contains(value) ? .accentColor : .gray)
                                    .controlSize(.small)
                            }
                        }
                    }
                }

                Section {
                    Toggle("启用这个计划", isOn: $isEnabled)
                    Text("请严格按医生或药师给出的信息录入。本应用仅用于提醒和记录，不提供诊断、剂量或补服建议。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 560, height: 650)
        .onChange(of: startDate) { _, newValue in
            if endDate < newValue { endDate = newValue }
        }
        .onChange(of: kind) { _, newValue in
            if newValue != .asNeeded && reminderTimes.isEmpty {
                reminderTimes = [DateSupport.time(on: .now, minutes: 8 * 60)]
            }
        }
    }

    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if kind == .asNeeded { return hasName }
        return hasName && !reminderTimes.isEmpty && !weekdays.isEmpty && (kind != .fixedCourse || endDate >= startDate)
    }

    private func toggleWeekday(_ value: Int) {
        if weekdays.contains(value) {
            guard weekdays.count > 1 else { return }
            weekdays.remove(value)
        } else {
            weekdays.insert(value)
        }
    }

    private func save() {
        let medication = Medication(
            id: medicationID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            strength: strength.trimmingCharacters(in: .whitespacesAndNewlines),
            doseAmount: doseAmount.trimmingCharacters(in: .whitespacesAndNewlines),
            form: form.trimmingCharacters(in: .whitespacesAndNewlines),
            route: route,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: createdAt
        )
        let minutes = kind == .asNeeded ? [] : reminderTimes.map { DateSupport.minutesSinceMidnight(for: $0) }
        let plan = MedicationPlan(
            id: planID,
            medicationID: medication.id,
            kind: kind,
            startDate: Calendar.current.startOfDay(for: startDate),
            endDate: kind == .fixedCourse ? Calendar.current.startOfDay(for: endDate) : nil,
            reminderMinutes: minutes,
            weekdays: kind == .asNeeded ? Array(1...7) : Array(weekdays),
            isEnabled: isEnabled,
            createdAt: planCreatedAt
        )
        storage.saveMedication(medication, plan: plan)
        service.dataDidChange()
        dismiss()
    }
}
