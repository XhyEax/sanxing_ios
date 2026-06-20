// Views/TimelineView.swift — 今日：多天无缝纵向滚动；整点 1 小时块；点选 + 长按拖拽多选
import SwiftUI
import SwiftData

// 记录各整点行（按 hour-start Date）在时间轴坐标系中的 frame，用于拖拽命中 + 焦点天跟踪
private struct RowFrameKey: PreferenceKey {
    static var defaultValue: [Date: CGRect] = [:]
    static func reduce(value: inout [Date: CGRect], nextValue: () -> [Date: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct TimelineView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \TimeBlock.start, order: .forward) private var allBlocks: [TimeBlock]
    @Query private var customCats: [CustomCategory]

    @State private var days: [Date] = []            // 渲染窗口（startOfDay 升序）
    @State private var focusedDay: Date = Date.now.startOfDay   // 顶部贴近的那天（随滚动更新）
    @State private var editing: TimeBlock?
    @State private var newBlock: NewBlock?
    @State private var selectionMode = false
    @State private var selected: Set<PersistentIdentifier> = []   // 选中的已有块
    @State private var selectedHourStarts: Set<Date> = []         // 选中的空闲整点（按 hour-start）
    @State private var showFillDialog = false
    @State private var showDatePicker = false
    @State private var datePickerDay = Date.now

    @State private var rowFrames: [Date: CGRect] = [:]
    @State private var dragAnchor: Date?
    @State private var scrollTarget: String?        // 顶部导航跳转目标（dayHeaderID）

    private struct NewBlock: Identifiable { let hourStart: Date; var id: Date { hourStart } }

    // MARK: - 取数（按天 / 按 hour-start）

    private func dayBlocks(of day: Date) -> [TimeBlock] {
        allBlocks.filter { $0.start.isSameDay(as: day) }
    }
    // 在该整点起始的块
    private func blocksStarting(at hs: Date) -> [TimeBlock] {
        let cal = Calendar.current
        let h = cal.component(.hour, from: hs)
        return allBlocks.filter { $0.start.isSameDay(as: hs) && cal.component(.hour, from: $0.start) == h }
    }
    // 在更早整点起始、却延伸覆盖此整点的多小时块（同一天内）→ 该整点不单独成行
    private func coveringBlock(at hs: Date) -> TimeBlock? {
        let cal = Calendar.current
        let h = cal.component(.hour, from: hs)
        return allBlocks.first {
            $0.start.isSameDay(as: hs) && cal.component(.hour, from: $0.start) != h
                && $0.start <= hs && $0.end > hs
        }
    }
    private func hourStarts(of day: Date) -> [Date] {
        let d0 = day.startOfDay
        return (0..<24).compactMap { Calendar.current.date(byAdding: .hour, value: $0, to: d0) }
    }
    private func visibleHourStarts(of day: Date) -> [Date] {
        hourStarts(of: day).filter { coveringBlock(at: $0) == nil }
    }
    private func emptyHourStarts(of day: Date) -> [Date] {
        visibleHourStarts(of: day).filter { blocksStarting(at: $0).isEmpty }
    }
    // 窗口内全部可见 hour-start（升序），供范围拖拽
    private var allVisibleHourStarts: [Date] { days.flatMap { visibleHourStarts(of: $0) } }

    private var nowHourStart: Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: cal.component(.hour, from: .now), minute: 0, second: 0,
                        of: Date.now.startOfDay) ?? Date.now.startOfDay
    }
    // 当前时刻是否落在此行（自身就是当前整点，或此行多小时块覆盖当前整点）
    private func rowContainsNow(_ hs: Date) -> Bool {
        guard hs.isSameDay(as: .now) else { return false }
        let cal = Calendar.current
        if cal.component(.hour, from: hs) == cal.component(.hour, from: .now) { return true }
        let ns = nowHourStart
        return blocksStarting(at: hs).contains { $0.start <= ns && $0.end > ns }
    }

    private var totalSelected: Int { selected.count + selectedHourStarts.count }
    private var focusedEmpty: [Date] { emptyHourStarts(of: focusedDay) }
    // 全选只针对「焦点天」的空闲整点
    private var allSelected: Bool {
        !focusedEmpty.isEmpty && focusedEmpty.allSatisfy { selectedHourStarts.contains($0) }
    }
    private var canMerge: Bool { selected.count == 1 && !selectedHourStarts.isEmpty }

    private func dayHeaderID(_ d: Date) -> String {
        "hdr-\(Int(d.startOfDay.timeIntervalSinceReferenceDate))"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(days, id: \.self) { day in
                            dayHeader(day)
                            ForEach(visibleHourStarts(of: day), id: \.self) { hs in
                                hourRow(hs)
                                    .id(hs)
                                    .background(GeometryReader { geo in
                                        Color.clear.preference(key: RowFrameKey.self,
                                            value: [hs: geo.frame(in: .named("timeline"))])
                                    })
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .coordinateSpace(name: "timeline")
                .onPreferenceChange(RowFrameKey.self) { frames in
                    rowFrames = frames
                    updateFocusedDay(frames)
                }
                .highPriorityGesture(selectDragGesture)
                .onChange(of: scrollTarget) { _, t in
                    guard let t else { return }
                    DispatchQueue.main.async {
                        withAnimation { proxy.scrollTo(t, anchor: .top) }
                        scrollTarget = nil
                    }
                }
                .onAppear { setupIfNeeded(proxy) }
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
            .sheet(item: $newBlock, onDismiss: afterEdit) {
                TimeBlockEditorView(day: $0.hourStart,
                                    hour: Calendar.current.component(.hour, from: $0.hourStart))
            }
            .sheet(item: $editing, onDismiss: afterEdit) { TimeBlockEditorView(block: $0) }
            .sheet(isPresented: $showDatePicker) {
                NavigationStack {
                    VStack {
                        DatePicker("跳转到", selection: $datePickerDay, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                            .padding()
                        Spacer()
                    }
                    .navigationTitle("选择日期")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("今天") { datePickerDay = .now }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showDatePicker = false; goToDay(datePickerDay) }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    // 所有改动后的统一收尾：跨午夜的块按 0 点拆开，再合并同一天内相邻同类块。
    // 填充 / 长按合并 / 编辑器关闭都走这里，保证跨天处理一致。
    private func normalize() {
        splitCrossDay()
        coalesceAdjacent()
    }
    private func afterEdit() { normalize() }

    // MARK: - 天头（白线分割 + 日期 + 当天小结）

    private func dayHeader(_ day: Date) -> some View {
        let blocks = dayBlocks(of: day)
        let total = blocks.reduce(0) { $0 + $1.duration }
        let isToday = day.isSameDay(as: .now)
        return VStack(spacing: 6) {
            Rectangle().fill(Color(.separator)).frame(height: 1)   // 跨天分割线（自适应深浅色）
            HStack {
                Text(isToday ? "今天" : day.dayTitle)
                    .font(.subheadline).bold()
                    .foregroundStyle(isToday ? Color.accentColor : .primary)
                Spacer()
                if !blocks.isEmpty {
                    Text("\(formatDuration(total)) · \(blocks.count) 块")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 12).padding(.bottom, 4)
        .id(dayHeaderID(day))
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
                    Label("填充\(selectedHourStarts.isEmpty ? "" : " \(selectedHourStarts.count)")",
                          systemImage: "rectangle.fill.badge.plus")
                }
                .disabled(selectedHourStarts.isEmpty)
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
                Button { datePickerDay = focusedDay; showDatePicker = true } label: {
                    Image(systemName: "calendar")
                }
            }
            ToolbarItem(placement: .principal) { dayNav }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("选择") { selectionMode = true }
            }
        }
    }

    // MARK: - 行

    private func hourRow(_ hs: Date) -> some View {
        let items = blocksStarting(at: hs)
        let isNow = rowContainsNow(hs)
        let h = Calendar.current.component(.hour, from: hs)
        return HStack(alignment: .top, spacing: 10) {
            Text(String(format: "%02d:00", h))
                .font(.caption).monospacedDigit()
                .fontWeight(isNow ? .bold : .regular)
                .underline(isNow, color: .accentColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(isNow ? Color.accentColor : .secondary)
                .frame(minWidth: 44, alignment: .leading)
                .padding(.top, 8)

            if items.isEmpty {
                emptySlot(hs)
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

    private func emptySlot(_ hs: Date) -> some View {
        let isSel = selectedHourStarts.contains(hs)
        return Button {
            if selectionMode { toggleHour(hs) } else { newBlock = NewBlock(hourStart: hs) }
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
            Button { goToDay(focusedDay.addingDays(-1)) } label: { Image(systemName: "chevron.left") }
            Button { goToDay(.now) } label: {
                Text(focusedDay.isSameDay(as: .now) ? "今天" : focusedDay.dayTitle)
                    .font(.subheadline).bold().lineLimit(1).fixedSize()
            }
            .buttonStyle(.plain)
            Button { goToDay(focusedDay.addingDays(1)) } label: { Image(systemName: "chevron.right") }
        }
    }

    // MARK: - 窗口 / 滚动

    // 窗口跨度：以中心天为基准前后各 windowRadius 天（够连续滚动多天；不在窗口内的目标由 goToDay 重建窗口）
    private static let windowRadius = 30

    private func setupIfNeeded(_ proxy: ScrollViewProxy) {
        guard days.isEmpty else { return }
        let t = Date.now.startOfDay
        days = (-Self.windowRadius...Self.windowRadius).map { t.addingDays($0) }
        focusedDay = t
        let vis = visibleHourStarts(of: t)
        let target = vis.last(where: { $0 <= nowHourStart }) ?? vis.first
        if let target { DispatchQueue.main.async { proxy.scrollTo(target, anchor: .top) } }
    }

    // 顶部贴近视口的那一行所属天 → focusedDay
    private func updateFocusedDay(_ frames: [Date: CGRect]) {
        let crossing = frames.first { $0.value.minY <= 1 && $0.value.maxY > 1 }?.key
        let fallback = frames.filter { $0.value.minY >= 0 }.min { $0.value.minY < $1.value.minY }?.key
        if let key = crossing ?? fallback {
            let d = key.startOfDay
            if d != focusedDay { focusedDay = d }
        }
    }

    private func goToDay(_ day: Date) {
        let d = day.startOfDay
        // 目标接近/超出窗口边缘 → 以它为中心重建窗口（即可继续往更早/更晚浏览）
        let nearEdge = d <= (days.first ?? d).addingDays(2) || d >= (days.last ?? d).addingDays(-2)
        if nearEdge {
            days = (-Self.windowRadius...Self.windowRadius).map { d.addingDays($0) }
        }
        focusedDay = d
        scrollTarget = dayHeaderID(d)
    }

    // MARK: - 长按拖拽多选

    private var selectDragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("timeline")))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if !selectionMode {
                    selectionMode = true
                    selected.removeAll(); selectedHourStarts.removeAll()
                }
                guard let hs = hourStart(at: drag.location) else { return }
                if dragAnchor == nil { dragAnchor = hs }
                selectRange(from: dragAnchor ?? hs, to: hs)
            }
            .onEnded { _ in dragAnchor = nil }
    }

    private func hourStart(at point: CGPoint) -> Date? {
        for (hs, rect) in rowFrames where point.y >= rect.minY && point.y <= rect.maxY { return hs }
        return nil
    }

    private func selectRange(from a: Date, to b: Date) {
        let ordered = allVisibleHourStarts
        guard let ia = ordered.firstIndex(of: a), let ib = ordered.firstIndex(of: b) else { return }
        let lo = min(ia, ib), hi = max(ia, ib)
        var ids: Set<PersistentIdentifier> = []
        var hours: Set<Date> = []
        for hs in ordered[lo...hi] {
            let items = blocksStarting(at: hs)
            if items.isEmpty { hours.insert(hs) } else { ids.formUnion(items.map { $0.id }) }
        }
        selected = ids
        selectedHourStarts = hours
    }

    // MARK: - 点选 / 批量操作

    private func tapBlock(_ b: TimeBlock) {
        if selectionMode {
            if selected.contains(b.id) { selected.remove(b.id) } else { selected.insert(b.id) }
        } else {
            editing = b
        }
    }
    private func toggleHour(_ hs: Date) {
        if selectedHourStarts.contains(hs) { selectedHourStarts.remove(hs) } else { selectedHourStarts.insert(hs) }
    }
    private func toggleSelectAll() {
        if allSelected { focusedEmpty.forEach { selectedHourStarts.remove($0) } }
        else { focusedEmpty.forEach { selectedHourStarts.insert($0) } }
    }
    private func exitSelection() {
        selectionMode = false; selected.removeAll(); selectedHourStarts.removeAll(); dragAnchor = nil
    }
    private func deleteSelected() {
        for b in allBlocks where selected.contains(b.id) { ctx.delete(b) }
        exitSelection()
    }
    // 把选中的空闲整点并入唯一选中的块：块拉长覆盖整段（保留块原有更早起/更晚止）
    private func mergeSelected() {
        guard let b = allBlocks.first(where: { selected.contains($0.id) }) else { return }
        let cal = Calendar.current
        let bhs = cal.date(bySettingHour: cal.component(.hour, from: b.start), minute: 0, second: 0,
                           of: b.start.startOfDay) ?? b.start
        let starts = selectedHourStarts.union([bhs])
        guard let lo = starts.min(), let hi = starts.max() else { return }
        b.start = min(b.start, lo)
        b.end = max(b.end, hi.addingTimeInterval(3600))
        normalize()
        exitSelection()
    }

    private func fillSelectedHours(with key: String) {
        for hs in selectedHourStarts {
            ctx.insert(TimeBlock(start: hs, end: hs.addingTimeInterval(3600), title: "", category: key))
        }
        normalize()
        exitSelection()
    }

    // 相邻且同类同名、且**同一自然日内**的块自动并成一个（跨天不合并）
    private func coalesceAdjacent() {
        let sorted = allBlocks.sorted { $0.start < $1.start }
        var prev: TimeBlock?
        for b in sorted {
            if let p = prev, p.category == b.category, p.title == b.title,
               b.start <= p.end, p.start.isSameDay(as: b.start) {
                p.end = max(p.end, b.end)
                if p.note.isEmpty { p.note = b.note }
                ctx.delete(b)
            } else {
                prev = b
            }
        }
    }

    // MARK: - 跨天拆分（0 点）

    // 跨午夜的块按 0 点拆开：原块裁到当天 24:00，其后每天的剩余段另建块（只填空闲、不覆盖已有块）。
    // 与「填充/选中设置」一致——跨天一律按天独立成块，不再保留一条跨天块。幂等（拆出的段都不跨天）。
    private func splitCrossDay() {
        let snapshot = allBlocks
        for b in snapshot {
            let firstMidnight = b.start.startOfDay.addingDays(1)
            guard b.end > firstMidnight else { continue }
            let originalEnd = b.end
            b.end = firstMidnight                       // 原块裁到起始日 24:00
            var dayStart = firstMidnight
            while dayStart < originalEnd {
                let dayEnd = dayStart.addingDays(1)
                insertIntoFreeSlots(category: b.category, title: b.title, note: b.note,
                                    from: dayStart, to: min(originalEnd, dayEnd),
                                    existing: snapshot, skip: b.id)
                dayStart = dayEnd
            }
        }
    }

    private func insertIntoFreeSlots(category: String, title: String, note: String,
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
