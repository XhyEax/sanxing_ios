// Views/TimelineView.swift — 今日：整点 1 小时块；点选 + 长按拖拽多选；空闲可选并批量填充
import SwiftUI
import SwiftData

// 记录各整点行在时间轴坐标系中的 frame，用于拖拽时命中
private struct RowFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct TimelineView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \TimeBlock.start, order: .forward) private var allBlocks: [TimeBlock]
    @Query private var customCats: [CustomCategory]

    @State private var selectedDay: Date = .now
    @State private var editing: TimeBlock?
    @State private var newBlock: NewBlock?
    @State private var selectionMode = false
    @State private var selected: Set<PersistentIdentifier> = []   // 选中的已有块
    @State private var selectedHours: Set<Int> = []               // 选中的空闲整点
    @State private var showFillDialog = false
    @State private var showDatePicker = false

    @State private var rowFrames: [Int: CGRect] = [:]
    @State private var dragAnchorHour: Int?

    private struct NewBlock: Identifiable { let hour: Int; var id: Int { hour } }

    private var dayBlocks: [TimeBlock] {
        allBlocks.filter { $0.start.isSameDay(as: selectedDay) }
    }
    private var totalTracked: TimeInterval { dayBlocks.reduce(0) { $0 + $1.duration } }
    // 在该整点起始的块
    private func blocksStarting(inHour h: Int) -> [TimeBlock] {
        dayBlocks.filter { Calendar.current.component(.hour, from: $0.start) == h }
    }
    // 在更早整点起始、却延伸覆盖此整点的多小时块；用它把被覆盖整点并入上方块、左侧钟点一并隐藏
    private func coveringBlock(inHour h: Int) -> TimeBlock? {
        let cal = Calendar.current
        guard let hStart = cal.date(bySettingHour: h, minute: 0, second: 0, of: selectedDay.startOfDay)
        else { return nil }
        return dayBlocks.first { cal.component(.hour, from: $0.start) != h && $0.start <= hStart && $0.end > hStart }
    }
    // 被多小时块覆盖的整点不再单独成行（合并时间后左侧钟点也随之合并）
    private var visibleHours: [Int] { (0..<24).filter { coveringBlock(inHour: $0) == nil } }
    private var emptyHours: [Int] { visibleHours.filter { blocksStarting(inHour: $0).isEmpty } }
    private var nowHour: Int { Calendar.current.component(.hour, from: .now) }
    // 当前时刻是否落在此可见行内：自身就是当前整点，或此行的多小时块覆盖了当前整点
    private func rowContainsNow(_ h: Int) -> Bool {
        guard selectedDay.isSameDay(as: .now) else { return false }
        if h == nowHour { return true }
        let cal = Calendar.current
        guard let nowStart = cal.date(bySettingHour: nowHour, minute: 0, second: 0,
                                      of: selectedDay.startOfDay) else { return false }
        return blocksStarting(inHour: h).contains { $0.start <= nowStart && $0.end > nowStart }
    }
    private var totalSelected: Int { selected.count + selectedHours.count }
    // 全选只针对空闲整点（默认不选已有块）
    private var allSelected: Bool { !emptyHours.isEmpty && selectedHours.count == emptyHours.count }
    // 仅 1 个块 + 若干空闲被选中 → 可把空闲并入该块（拉长覆盖整段）
    private var canMerge: Bool { selected.count == 1 && !selectedHours.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        header
                        ForEach(visibleHours, id: \.self) { h in
                            hourRow(h)
                                .id(h)
                                .background(GeometryReader { geo in
                                    Color.clear.preference(key: RowFrameKey.self,
                                        value: [h: geo.frame(in: .named("timeline"))])
                                })
                        }
                    }
                    .padding(.horizontal)
                }
                .coordinateSpace(name: "timeline")
                .onPreferenceChange(RowFrameKey.self) { rowFrames = $0 }
                // 长按某行后不抬手、上下滑动连续多选
                .highPriorityGesture(selectDragGesture)
                .onAppear {
                    if selectedDay.isSameDay(as: .now) {
                        proxy.scrollTo(max(0, nowHour - 1), anchor: .top)
                    }
                }
            }
            .navigationTitle(selectionMode ? "已选 \(totalSelected)" : "今日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showFillDialog) {
                NavigationStack {
                    ScrollView {
                        CategoryGrid(selectedKey: nil) { key in
                            fillSelectedHours(with: key)
                            showFillDialog = false
                        }
                        .padding()
                    }
                    .navigationTitle("填充为")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { showFillDialog = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $newBlock, onDismiss: afterEdit) { TimeBlockEditorView(day: selectedDay, hour: $0.hour) }
            .sheet(item: $editing, onDismiss: afterEdit) { TimeBlockEditorView(block: $0) }
            .sheet(isPresented: $showDatePicker) {
                NavigationStack {
                    VStack {
                        DatePicker("跳转到", selection: $selectedDay, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                            .padding()
                        Spacer()
                    }
                    .navigationTitle("选择日期")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("今天") { selectedDay = .now }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showDatePicker = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    // 编辑器关闭后：先按天复制跨天块，再合并相邻同类块
    private func afterEdit() {
        propagateCrossDay()
        coalesceAdjacent()
    }

    private var header: some View {
        HStack {
            Text("已记录 \(formatDuration(totalTracked)) · 共 \(dayBlocks.count) 块")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if selectionMode {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(allSelected ? "取消全选" : "全选") { toggleSelectAll() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完成") { exitSelection() }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button { showFillDialog = true } label: {
                    Label("填充\(selectedHours.isEmpty ? "" : " \(selectedHours.count)")",
                          systemImage: "rectangle.fill.badge.plus")
                }
                .disabled(selectedHours.isEmpty)
                Spacer()
                if canMerge {
                    Button("合并") { mergeSelected() }
                    Spacer()
                }
                Button(role: .destructive) { deleteSelected() } label: {
                    Label("删除\(selected.isEmpty ? "" : " \(selected.count)")", systemImage: "trash")
                }
                .disabled(selected.isEmpty)
            }
        } else {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showDatePicker = true } label: { Image(systemName: "calendar") }
            }
            ToolbarItem(placement: .principal) { dayNav }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("选择") { selectionMode = true }
            }
        }
    }

    // 单个整点行
    private func hourRow(_ h: Int) -> some View {
        let items = blocksStarting(inHour: h)
        let isNow = rowContainsNow(h)
        return HStack(alignment: .top, spacing: 10) {
            Text(String(format: "%02d:00", h))
                .font(.caption).monospacedDigit()
                .fontWeight(isNow ? .bold : .regular)
                .underline(isNow, color: .accentColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)   // 任意字体大小都单行
                .foregroundStyle(isNow ? Color.accentColor : .secondary)
                .frame(minWidth: 44, alignment: .leading)
                .padding(.top, 8)

            if items.isEmpty {
                emptySlot(h)
            } else {
                VStack(spacing: 6) {
                    ForEach(items) { b in
                        Button { tapBlock(b) } label: { blockCard(b) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func emptySlot(_ h: Int) -> some View {
        let isSel = selectedHours.contains(h)
        return Button {
            if selectionMode { toggleHour(h) } else { newBlock = NewBlock(hour: h) }
        } label: {
            HStack {
                if selectionMode {
                    Image(systemName: isSel ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSel ? Color.accentColor : .secondary)
                }
                Text("空闲").font(.subheadline).foregroundStyle(.tertiary)
                Spacer()
                if !selectionMode { Image(systemName: "plus").font(.caption).foregroundStyle(.tertiary) }
            }
            .padding(.vertical, 10).padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background((isSel ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06)),
                        in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func blockCard(_ b: TimeBlock) -> some View {
        let isSel = selected.contains(b.id)
        let s = catStyle(for: b.category, custom: customCats)
        return HStack(spacing: 10) {
            if selectionMode {
                Image(systemName: isSel ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSel ? Color.accentColor : .secondary)
            }
            RoundedRectangle(cornerRadius: 3).fill(s.color).frame(width: 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(b.title.isEmpty ? s.name : b.title).font(.subheadline)
                HStack(spacing: 6) {
                    Label(s.name, systemImage: s.icon).font(.caption2).foregroundStyle(s.color)
                    Text("· \(b.start.hm)-\(b.end.hm) · \(formatDuration(b.duration))")
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background((isSel ? s.color.opacity(0.20) : s.color.opacity(0.10)),
                    in: RoundedRectangle(cornerRadius: 8))
    }

    private var dayNav: some View {
        HStack(spacing: 12) {
            Button { selectedDay = selectedDay.addingDays(-1) } label: { Image(systemName: "chevron.left") }
            Button { selectedDay = .now } label: {
                Text(selectedDay.isSameDay(as: .now) ? "今天" : selectedDay.dayTitle)
                    .font(.subheadline).bold().lineLimit(1).fixedSize()
            }
            .buttonStyle(.plain)
            Button { selectedDay = selectedDay.addingDays(1) } label: { Image(systemName: "chevron.right") }
        }
    }

    // MARK: - 长按拖拽多选

    private var selectDragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("timeline")))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if !selectionMode {
                    selectionMode = true
                    selected.removeAll(); selectedHours.removeAll()
                }
                guard let h = hour(at: drag.location) else { return }
                if dragAnchorHour == nil { dragAnchorHour = h }
                selectRange(from: dragAnchorHour ?? h, to: h)
            }
            .onEnded { _ in dragAnchorHour = nil }
    }

    private func hour(at point: CGPoint) -> Int? {
        for (h, rect) in rowFrames where point.y >= rect.minY && point.y <= rect.maxY { return h }
        return nil
    }

    private func selectRange(from a: Int, to b: Int) {
        let lo = min(a, b), hi = max(a, b)
        var blockIDs: Set<PersistentIdentifier> = []
        var hours: Set<Int> = []
        for h in lo...hi {
            let items = blocksStarting(inHour: h)
            if !items.isEmpty { blockIDs.formUnion(items.map { $0.id }) }
            else if let cov = coveringBlock(inHour: h) { blockIDs.insert(cov.id) }  // 被覆盖整点归入其多小时块
            else { hours.insert(h) }
        }
        selected = blockIDs
        selectedHours = hours
    }

    // MARK: - 点选 / 批量操作

    private func tapBlock(_ b: TimeBlock) {
        if selectionMode {
            if selected.contains(b.id) { selected.remove(b.id) } else { selected.insert(b.id) }
        } else {
            editing = b
        }
    }
    private func toggleHour(_ h: Int) {
        if selectedHours.contains(h) { selectedHours.remove(h) } else { selectedHours.insert(h) }
    }
    private func toggleSelectAll() {
        // 全选/取消全选只覆盖空闲整点，保留用户手动选中的块
        if allSelected { selectedHours.removeAll() } else { selectedHours = Set(emptyHours) }
    }
    private func exitSelection() {
        selectionMode = false; selected.removeAll(); selectedHours.removeAll(); dragAnchorHour = nil
    }
    private func deleteSelected() {
        for b in dayBlocks where selected.contains(b.id) { ctx.delete(b) }
        exitSelection()
    }
    // 把选中的空闲整点并入唯一选中的块：块拉长到覆盖整段（保留块原有的更早起/更晚止）
    private func mergeSelected() {
        guard let b = dayBlocks.first(where: { selected.contains($0.id) }) else { return }
        let cal = Calendar.current
        let blockHour = cal.component(.hour, from: b.start)
        let hours = selectedHours.union([blockHour])
        guard let lo = hours.min(), let hi = hours.max() else { return }
        let day0 = selectedDay.startOfDay
        let loStart = cal.date(bySettingHour: lo, minute: 0, second: 0, of: day0) ?? day0
        let hiEnd = (cal.date(bySettingHour: hi, minute: 0, second: 0, of: day0) ?? day0)
            .addingTimeInterval(3600)
        b.start = min(b.start, loStart)
        b.end = max(b.end, hiEnd)
        coalesceAdjacent()
        exitSelection()
    }

    private func fillSelectedHours(with key: String) {
        let cal = Calendar.current
        for h in selectedHours {
            let start = cal.date(bySettingHour: h, minute: 0, second: 0, of: selectedDay.startOfDay)
                ?? selectedDay.startOfDay
            ctx.insert(TimeBlock(start: start, end: start.addingTimeInterval(3600),
                                 title: "", category: key))
        }
        coalesceAdjacent()
        exitSelection()
    }

    // 相邻且同类同名的块自动并成一个（如连续填充的多个 1 小时同类块、编辑后与邻块相接）
    private func coalesceAdjacent() {
        let sorted = dayBlocks.sorted { $0.start < $1.start }
        var prev: TimeBlock?
        for b in sorted {
            if let p = prev, p.category == b.category, p.title == b.title, b.start <= p.end {
                p.end = max(p.end, b.end)           // 接上/重叠 → 拉长前块
                if p.note.isEmpty { p.note = b.note }
                ctx.delete(b)
            } else {
                prev = b
            }
        }
    }

    // MARK: - 跨天复制

    // 跨午夜的块，在其后每个被覆盖的日子里按「空闲时段」复制一份同类块；
    // 只填空闲、不覆盖已有块（次日已有块则跳过）。幂等：副本本身不跨天，重跑时旧副本已占槽自动跳过。
    private func propagateCrossDay() {
        let snapshot = allBlocks               // 快照，避免边遍历边插入
        for b in snapshot {
            let firstMidnight = b.start.startOfDay.addingDays(1)   // 起始日之后的第一个午夜
            guard b.end > firstMidnight else { continue }          // 不跨天则跳过
            var dayStart = firstMidnight
            while dayStart < b.end {
                let dayEnd = dayStart.addingDays(1)
                copyIntoFreeSlots(category: b.category, title: b.title, note: b.note,
                                  from: dayStart, to: min(b.end, dayEnd),
                                  existing: snapshot, skip: b.id)
                dayStart = dayEnd
            }
        }
    }

    // 在 [from, to) 内，挖掉与已有块（skip 除外）重叠的部分，对每段剩余空闲插入同类块
    private func copyIntoFreeSlots(category: String, title: String, note: String,
                                   from: Date, to: Date,
                                   existing: [TimeBlock], skip: PersistentIdentifier) {
        let busy = existing
            .filter { $0.id != skip && $0.end > from && $0.start < to }
            .map { (start: max($0.start, from), end: min($0.end, to)) }
            .sorted { $0.start < $1.start }
        var cursor = from
        for seg in busy {
            if seg.start > cursor {
                ctx.insert(TimeBlock(start: cursor, end: seg.start,
                                     title: title, category: category, note: note))
            }
            cursor = max(cursor, seg.end)
        }
        if cursor < to {
            ctx.insert(TimeBlock(start: cursor, end: to,
                                 title: title, category: category, note: note))
        }
    }
}
