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
    var goTodayTrigger: Int = 0   // 点「今日」Tab 时 +1 → 滚回今日

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
    @State private var selectedIdle: Set<IdleRange> = []          // 选中的小空闲段（块之间任意长度）
    @State private var showFillDialog = false
    @State private var showDatePicker = false
    @State private var datePickerDay = Date.now

    @State private var rowFrames: [Date: CGRect] = [:]
    @State private var dragAnchor: Date?
    @State private var scrollTarget: String?        // 顶部导航跳转目标（dayHeaderID）
    @State private var overlap: OverlapPair?        // 编辑后检测到的重叠，弹窗让用户选择如何处理

    private struct NewBlock: Identifiable { let start: Date; let end: Date; var id: Date { start } }
    private struct OverlapPair: Identifiable { let id = UUID(); let earlier: TimeBlock; let later: TimeBlock }
    private struct IdleRange: Hashable { let start: Date; let end: Date }

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
        hourStarts(of: day).filter { hs in
            if !blocksStarting(at: hs).isEmpty { return true }   // 有块起始于此 → 显示（含与前块重叠的情形）
            let he = hs.addingTimeInterval(3600)
            // 整段被多小时块覆盖且无块 → 隐藏；若覆盖块在本整点内结束（留有空闲）→ 仍显示，渲染那段空闲
            if let cov = coveringBlock(at: hs), cov.end >= he { return false }
            return true
        }
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
    // 当前时刻是否落在 [s, e) 内（用于高亮当前行）
    private func isNowIn(_ s: Date, _ e: Date) -> Bool {
        let now = Date.now
        return s <= now && now < e
    }
    // 24 小时制时钟标签 "HH:mm"
    private func clock(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private var totalSelected: Int { selected.count + selectedHourStarts.count + selectedIdle.count }
    private var selectedIdleCount: Int { selectedHourStarts.count + selectedIdle.count }   // 可填充的空闲数
    private var focusedEmpty: [Date] { emptyHourStarts(of: focusedDay) }
    private var focusedIdle: [IdleRange] { idleRanges(of: focusedDay) }
    // 全选「焦点天」的空闲整点 + 小空闲段
    private var allSelected: Bool {
        let any = !focusedEmpty.isEmpty || !focusedIdle.isEmpty
        return any
            && focusedEmpty.allSatisfy { selectedHourStarts.contains($0) }
            && focusedIdle.allSatisfy { selectedIdle.contains($0) }
    }
    // 恰好选中一个块时返回它（底部「操作」菜单用）
    private var singleBlock: TimeBlock? {
        guard selected.count == 1, let id = selected.first else { return nil }
        return allBlocks.first { $0.id == id }
    }

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
                .onChange(of: goTodayTrigger) { _, _ in goToDay(.now) }
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
                TimeBlockEditorView(start: $0.start, end: $0.end)
            }
            .sheet(item: $editing, onDismiss: afterEdit) { TimeBlockEditorView(block: $0) }
            .confirmationDialog("时间重叠", isPresented: Binding(
                get: { overlap != nil }, set: { if !$0 { overlap = nil } }
            ), titleVisibility: .visible, presenting: overlap) { p in
                Button("把「\(blockName(p.later))」开始改到 \(clock(p.earlier.end))") { resolveMovingLater(p) }
                Button("把「\(blockName(p.earlier))」结束改到 \(clock(p.later.start))") { resolveMovingEarlier(p) }
                Button("保持重叠", role: .cancel) { overlap = nil }
            } message: { p in
                Text("「\(blockName(p.earlier))」(到 \(clock(p.earlier.end))) 与「\(blockName(p.later))」(\(clock(p.later.start)) 起) 重叠，是否同步调整？")
            }
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
    private func afterEdit() {
        normalize()
        checkOverlap()
    }

    // 编辑后若有「不同分类」的相邻块时间重叠（同类已被 coalesce 合并），弹窗让用户选择如何处理
    private func checkOverlap() {
        let sorted = allBlocks.sorted { $0.start < $1.start }
        guard sorted.count > 1 else { return }
        for k in 1..<sorted.count {
            let a = sorted[k - 1], b = sorted[k]
            if a.start.isSameDay(as: b.start), a.end > b.start {
                overlap = OverlapPair(earlier: a, later: b)
                return
            }
        }
    }

    private func blockName(_ b: TimeBlock) -> String {
        b.title.isEmpty ? catStyle(for: b.category, custom: customCats).name : b.title
    }

    // 顺移后块：后块开始改到前块结束（被完全覆盖则删除）
    private func resolveMovingLater(_ p: OverlapPair) {
        if p.earlier.end < p.later.end { p.later.start = p.earlier.end } else { ctx.delete(p.later) }
        overlap = nil
        afterEdit()   // 继续规整并检测下一处重叠
    }
    // 缩短前块：前块结束改到后块开始（变空则删除）
    private func resolveMovingEarlier(_ p: OverlapPair) {
        if p.earlier.start < p.later.start { p.earlier.end = p.later.start } else { ctx.delete(p.earlier) }
        overlap = nil
        afterEdit()
    }

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
                    Label("填充\(selectedIdleCount == 0 ? "" : " \(selectedIdleCount)")",
                          systemImage: "rectangle.fill.badge.plus")
                }
                .disabled(selectedIdleCount == 0)
                if let b = singleBlock {
                    if Date.now < b.end {   // 开始改为现在
                        Spacer()
                        Button { setStartNow(b); exitSelection() } label: { Image(systemName: "arrow.right.to.line") }
                    }
                    if Date.now > b.start {   // 结束改为现在
                        Spacer()
                        Button { setEndNow(b); exitSelection() } label: { Image(systemName: "stop.circle") }
                    }
                    if selectedIdleCount > 0 {   // 并入选中空闲
                        Spacer()
                        Button { mergeSelected() } label: { Image(systemName: "arrow.triangle.merge") }
                    }
                    if hasGapBefore(b) {   // 合并前面空闲
                        Spacer()
                        Button { mergeGapBefore(b); exitSelection() } label: { Image(systemName: "arrow.up.to.line") }
                    }
                    if hasGapAfter(b) {    // 合并后面空闲
                        Spacer()
                        Button { mergeGapAfter(b); exitSelection() } label: { Image(systemName: "arrow.down.to.line") }
                    }
                }
                Spacer()
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

    // 一个整点里按时间顺序排出的条目：空整点槽 / 块 / 块之间的空闲段（任意长度都显示）
    private enum HourItem: Identifiable {
        case empty(Date)            // 整点空闲槽（可多选/填充）
        case block(TimeBlock)
        case idle(Date, Date)       // 块之间剩余的空闲（展示 + 点按建块）
        var id: String {
            switch self {
            case .empty(let d): return "e\(d.timeIntervalSinceReferenceDate)"
            case .block(let b): return "b\(ObjectIdentifier(b).hashValue)"
            case .idle(let s, _): return "i\(s.timeIntervalSinceReferenceDate)"
            }
        }
    }

    private func hourItems(_ hs: Date) -> [HourItem] {
        let he = hs.addingTimeInterval(3600)
        let blocks = blocksStarting(at: hs).sorted { $0.start < $1.start }
        let cov = coveringBlock(at: hs)
        // 游标从整点起；若被前一个多小时块占用了开头，跳到它的结束（那段不算空闲）
        var cursor = hs
        if let cov { cursor = min(he, max(cursor, cov.end)) }

        if blocks.isEmpty {
            if cov == nil { return [.empty(hs)] }              // 完全空 → 整点空闲槽
            return cursor < he ? [.idle(cursor, he)] : []      // 覆盖块在本整点内结束 → 渲染剩余空闲
        }

        var items: [HourItem] = []
        for b in blocks {
            if b.start > cursor { items.append(.idle(cursor, b.start)) }   // 块前空闲（非整点起始也会显示）
            items.append(.block(b))
            cursor = max(cursor, b.end)
        }
        if cursor < he { items.append(.idle(cursor, he)) }                 // 块后到整点末的空闲
        return items
    }

    private func hourRow(_ hs: Date) -> some View {
        VStack(spacing: 6) {
            ForEach(hourItems(hs)) { item in itemRow(item) }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func itemRow(_ item: HourItem) -> some View {
        switch item {
        case .empty(let hs):
            timeLabeledRow(time: hs, isNow: isNowIn(hs, hs.addingTimeInterval(3600))) {
                emptySlot(hs)
            }
        case .block(let b):
            timeLabeledRow(time: b.start, isNow: isNowIn(b.start, b.end)) {
                Button { tapBlock(b) } label: { blockCard(b) }.buttonStyle(.plain)
            }
        case .idle(let s, let e):
            timeLabeledRow(time: s, isNow: isNowIn(s, e)) { idleGap(s, e) }
        }
    }

    private func timeLabeledRow<C: View>(time: Date, isNow: Bool,
                                         @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(clock(time))
                .font(.caption).monospacedDigit()
                .fontWeight(isNow ? .bold : .regular)
                .underline(isNow, color: .accentColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(isNow ? Color.accentColor : .secondary)
                .frame(minWidth: 44, alignment: .leading)
                .padding(.top, 8)
            content()
        }
    }

    // 块之间的空闲段：普通态点按建块；多选态可勾选（一并填充/合并）
    private func idleGap(_ s: Date, _ e: Date) -> some View {
        let r = IdleRange(start: s, end: e)
        let isSel = selectedIdle.contains(r)
        return Button {
            if selectionMode { toggleIdle(r) } else { newBlock = NewBlock(start: s, end: e) }
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

    // 某天所有可见的小空闲段（供全选）
    private func idleRanges(of day: Date) -> [IdleRange] {
        visibleHourStarts(of: day).flatMap { hs in
            hourItems(hs).compactMap { if case .idle(let s, let e) = $0 { return IdleRange(start: s, end: e) }; return nil }
        }
    }

    private func emptySlot(_ hs: Date) -> some View {
        let isSel = selectedHourStarts.contains(hs)
        return Button {
            if selectionMode { toggleHour(hs) }
            else { newBlock = NewBlock(start: hs, end: hs.addingTimeInterval(3600)) }
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
                    selected.removeAll(); selectedHourStarts.removeAll(); selectedIdle.removeAll()
                }
                guard let hs = hourStart(at: drag.location) else { return }
                if dragAnchor == nil { dragAnchor = hs }
                selectRange(from: dragAnchor ?? hs, to: hs)
            }
            .onEnded { _ in
                dragAnchor = nil
                // 选中的全是空闲（没有块）→ 直接弹分类/事件选择填充
                if selected.isEmpty && selectedIdleCount > 0 { showFillDialog = true }
            }
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
        var idles: Set<IdleRange> = []
        for hs in ordered[lo...hi] {
            for item in hourItems(hs) {     // 选中该整点里的全部条目：块 / 空整点 / 小空闲段
                switch item {
                case .empty(let h): hours.insert(h)
                case .block(let bl): ids.insert(bl.id)
                case .idle(let s, let e): idles.insert(IdleRange(start: s, end: e))
                }
            }
        }
        selected = ids
        selectedHourStarts = hours
        selectedIdle = idles
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
    private func toggleIdle(_ r: IdleRange) {
        if selectedIdle.contains(r) { selectedIdle.remove(r) } else { selectedIdle.insert(r) }
    }
    private func toggleSelectAll() {
        if allSelected {
            focusedEmpty.forEach { selectedHourStarts.remove($0) }
            focusedIdle.forEach { selectedIdle.remove($0) }
        } else {
            focusedEmpty.forEach { selectedHourStarts.insert($0) }
            focusedIdle.forEach { selectedIdle.insert($0) }
        }
    }
    private func exitSelection() {
        selectionMode = false
        selected.removeAll(); selectedHourStarts.removeAll(); selectedIdle.removeAll(); dragAnchor = nil
    }
    private func deleteSelected() {
        for b in allBlocks where selected.contains(b.id) { ctx.delete(b) }
        exitSelection()
    }
    // 把选中的空闲整点并入唯一选中的块：块拉长覆盖整段（保留块原有更早起/更晚止）
    private func mergeSelected() {
        guard let b = allBlocks.first(where: { selected.contains($0.id) }) else { return }
        var lo = b.start, hi = b.end
        for hs in selectedHourStarts { lo = min(lo, hs); hi = max(hi, hs.addingTimeInterval(3600)) }
        for r in selectedIdle { lo = min(lo, r.start); hi = max(hi, r.end) }
        b.start = lo
        b.end = hi
        normalize()
        exitSelection()
    }

    private func fillSelectedHours(with key: String) {
        for hs in selectedHourStarts {
            ctx.insert(TimeBlock(start: hs, end: hs.addingTimeInterval(3600), title: "", category: key))
        }
        for r in selectedIdle {
            ctx.insert(TimeBlock(start: r.start, end: r.end, title: "", category: key))   // 小空闲段按精确起止建块
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

    // MARK: - 单块操作（底部「操作」菜单调用）

    // 把开始/结束改为当前时刻
    private func setStartNow(_ b: TimeBlock) {
        let now = Date.now
        guard now < b.end else { return }
        b.start = now
        afterEdit()
    }
    private func setEndNow(_ b: TimeBlock) {
        let now = Date.now
        guard now > b.start else { return }
        b.end = now
        afterEdit()
    }
    // 同一天内、结束在本块开始之前、最靠近的那个块
    private func previousBlock(before b: TimeBlock) -> TimeBlock? {
        allBlocks.filter { $0.id != b.id && $0.start.isSameDay(as: b.start) && $0.end <= b.start }
            .max { $0.end < $1.end }
    }
    // 同一天内、开始在本块结束之后、最靠近的那个块
    private func nextBlock(after b: TimeBlock) -> TimeBlock? {
        allBlocks.filter { $0.id != b.id && $0.start.isSameDay(as: b.start) && $0.start >= b.end }
            .min { $0.start < $1.start }
    }
    private func hasGapAfter(_ b: TimeBlock) -> Bool {
        guard let n = nextBlock(after: b) else { return false }
        return n.start > b.end
    }
    // 把结束延后到下一个块的开始，吸收后面的空闲
    private func mergeGapAfter(_ b: TimeBlock) {
        guard let n = nextBlock(after: b), n.start > b.end else { return }
        b.end = n.start
        afterEdit()
    }
    private func hasGapBefore(_ b: TimeBlock) -> Bool {
        guard let p = previousBlock(before: b) else { return false }
        return p.end < b.start
    }
    // 把开始时间提前到前一个块的结束，吸收两者之间的空闲（同类同名则被 coalesce 并成一条）
    private func mergeGapBefore(_ b: TimeBlock) {
        guard let p = previousBlock(before: b), p.end < b.start else { return }
        b.start = p.end
        normalize()
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
