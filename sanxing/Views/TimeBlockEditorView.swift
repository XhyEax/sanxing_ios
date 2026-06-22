// Views/TimeBlockEditorView.swift — 新建/编辑时间块
import SwiftUI
import SwiftData

struct TimeBlockEditorView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var customCats: [CustomCategory]

    // 时长预设（分钟）：快速选择，结束时间自动由「开始 + 时长」算出
    private static let presetMinutes = [15, 30, 45, 60]

    private let existing: TimeBlock?
    @State private var title: String
    @State private var categoryKey: String
    @State private var start: Date
    @State private var end: Date
    @State private var durationMinutes: Int
    @State private var note: String

    // 新建：默认时长 1 小时。指定 hour 则从该整点起；否则当天用当前整点、他天用 9 点
    init(day: Date, hour: Int? = nil) {
        existing = nil
        let cal = Calendar.current
        let base: Date
        if let h = hour {
            base = cal.date(bySettingHour: h, minute: 0, second: 0, of: day.startOfDay) ?? day.startOfDay
        } else if day.isSameDay(as: .now) {
            base = cal.date(bySetting: .minute, value: 0, of: .now) ?? .now
        } else {
            base = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day.startOfDay) ?? day.startOfDay
        }
        _title = State(initialValue: "")
        _categoryKey = State(initialValue: BlockCategory.think.rawValue)
        _start = State(initialValue: base)
        _end = State(initialValue: base.addingTimeInterval(3600))
        _durationMinutes = State(initialValue: 60)
        _note = State(initialValue: "")
    }

    // 新建：指定精确起止（点空闲段建块用）
    init(start: Date, end: Date) {
        existing = nil
        _title = State(initialValue: "")
        _categoryKey = State(initialValue: BlockCategory.think.rawValue)
        _start = State(initialValue: start)
        _end = State(initialValue: end)
        let mins = Int(end.timeIntervalSince(start) / 60)
        _durationMinutes = State(initialValue: Self.presetMinutes.contains(mins) ? mins : 60)
        _note = State(initialValue: "")
    }

    // 编辑
    init(block: TimeBlock) {
        existing = block
        _title = State(initialValue: block.title)
        _categoryKey = State(initialValue: block.category)
        _start = State(initialValue: block.start)
        _end = State(initialValue: block.end)
        // 已有块时长若正好匹配某预设则选中，否则默认 1 小时
        let mins = Int(block.duration / 60)
        _durationMinutes = State(initialValue: Self.presetMinutes.contains(mins) ? mins : 60)
        _note = State(initialValue: block.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("做什么（可留空）", text: $title)
                }
                Section("备注") {
                    TextField("备注", text: $note, axis: .vertical).lineLimit(2...6)
                }
                Section("分类") {
                    CategoryGrid(selectedKey: categoryKey) { categoryKey = $0 }
                }
                Section("时间") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("时长").font(.subheadline).foregroundStyle(.secondary)
                        Picker("时长", selection: $durationMinutes) {
                            ForEach(Self.presetMinutes, id: \.self) { m in
                                Text(m == 60 ? "1小时" : "\(m)分钟").tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 2)
                    DatePicker("开始", selection: $start)
                    DatePicker("结束", selection: $end)   // 自动算出，也可手动改
                    // 表盘：拖把手改起止（仿健康 App）
                    ClockDialPicker(start: $start, end: $end,
                                    color: catStyle(for: categoryKey, custom: customCats).color,
                                    startIcon: catStyle(for: categoryKey, custom: customCats).icon)
                        .padding(.top, 4)
                }
                // 选时长 → 自动设结束（拖把手/改起止则各自独立调整，互不牵连）
                .onChange(of: durationMinutes) { _, m in
                    end = start.addingTimeInterval(TimeInterval(m * 60))
                }
            }
            .navigationTitle(existing == nil ? "新建时间块" : "编辑时间块")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                    // 终止：只对已有块（编辑态）显示；从空闲新建块时不显示
                    if existing != nil {
                        Button {
                            guard Date.now > start else { return }
                            end = Date.now
                            save()
                        } label: {
                            Image(systemName: "stop.circle")
                        }
                        .tint(.red)
                        .disabled(Date.now <= start)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if existing != nil {
                        Button("删除", role: .destructive) { delete() }
                            .tint(.red)
                    }
                    Button("保存") { save() }.fontWeight(.semibold).disabled(end <= start)
                }
            }
        }
    }

    private func save() {
        if let b = existing {
            b.title = title; b.category = categoryKey
            b.start = start; b.end = end; b.note = note
        } else {
            ctx.insert(TimeBlock(start: start, end: end, title: title,
                                 category: categoryKey, note: note))
        }
        dismiss()
    }

    private func delete() {
        if let b = existing { ctx.delete(b) }
        dismiss()
    }
}
