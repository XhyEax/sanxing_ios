// Views/TimeBlockEditorView.swift — 新建/编辑时间块
import SwiftUI
import SwiftData

struct TimeBlockEditorView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    private let existing: TimeBlock?
    @State private var title: String
    @State private var category: BlockCategory
    @State private var start: Date
    @State private var end: Date
    @State private var note: String

    // 新建：默认从当天当前小时起，时长 1 小时
    init(day: Date) {
        existing = nil
        let cal = Calendar.current
        let base: Date
        if day.isSameDay(as: .now) {
            base = cal.date(bySetting: .minute, value: 0, of: .now) ?? .now
        } else {
            base = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day.startOfDay) ?? day.startOfDay
        }
        _title = State(initialValue: "")
        _category = State(initialValue: .other)
        _start = State(initialValue: base)
        _end = State(initialValue: base.addingTimeInterval(3600))
        _note = State(initialValue: "")
    }

    // 编辑
    init(block: TimeBlock) {
        existing = block
        _title = State(initialValue: block.title)
        _category = State(initialValue: block.cat)
        _start = State(initialValue: block.start)
        _end = State(initialValue: block.end)
        _note = State(initialValue: block.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("做什么（可留空）", text: $title)
                }
                Section("分类") {
                    categoryPicker
                }
                Section("时间") {
                    DatePicker("开始", selection: $start)
                    DatePicker("结束", selection: $end)
                    HStack {
                        Text("时长").foregroundStyle(.secondary)
                        Spacer()
                        Text(formatDuration(max(0, end.timeIntervalSince(start))))
                            .foregroundStyle(end > start ? Color.primary : Color.red)
                    }
                }
                Section("备注") {
                    TextField("备注", text: $note, axis: .vertical).lineLimit(2...6)
                }
                if existing != nil {
                    Section {
                        Button("删除", role: .destructive) { delete() }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(existing == nil ? "新建时间块" : "编辑时间块")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(end <= start)
                }
            }
        }
    }

    private var categoryPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
            ForEach(BlockCategory.allCases) { c in
                Button { category = c } label: {
                    VStack(spacing: 4) {
                        Image(systemName: c.icon).font(.title3)
                        Text(c.name).font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(category == c ? c.color.opacity(0.18) : Color.secondary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(category == c ? c.color : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        if let b = existing {
            b.title = title; b.category = category.rawValue
            b.start = start; b.end = end; b.note = note
        } else {
            ctx.insert(TimeBlock(start: start, end: end, title: title,
                                 category: category.rawValue, note: note))
        }
        dismiss()
    }

    private func delete() {
        if let b = existing { ctx.delete(b) }
        dismiss()
    }
}
