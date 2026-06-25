// Views/TimelineView.swift — 今日：多天无缝纵向滚动；整点 1 小时块；点选 + 长按拖拽多选
import SwiftUI
import SwiftData
import UIKit

// 各整点行 frame（仅多选态上报，用于拖拽命中）
private struct RowFrameKey: PreferenceKey {
    static var defaultValue: [Date: CGRect] = [:]
    static func reduce(value: inout [Date: CGRect], nextValue: () -> [Date: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// 各天 header frame（始终上报，但每天仅 1 个，用于跟踪焦点天，比逐行上报便宜得多）
private struct DayFrameKey: PreferenceKey {
    static var defaultValue: [Date: CGRect] = [:]
    static func reduce(value: inout [Date: CGRect], nextValue: () -> [Date: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// 按天分组的块缓存：每次 body 求值时整体重建一次，渲染期各行只做字典查找，
// 不再每行 filter 整个 allBlocks（引用类型，重建不触发额外刷新）
private final class DayBlocksCache { var byDay: [Date: [TimeBlock]] = [:] }

struct TimelineView: View {
    var goTodayTrigger: Int = 0   // 点「时间轴」Tab 时 +1 → 跳当前第一个空闲

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
    @State private var showMergeTargetDialog = false   // 多个有名块合并：选合并成哪个
    @State private var showDatePicker = false
    @State private var datePickerDay = Date.now

    @State private var rowFrames: [Date: CGRect] = [:]
    @State private var dayFrames: [Date: CGRect] = [:]   // 各天 header 在视口中的位置（判可见天）
    @State private var dragAnchor: Date?
    @State private var scrolledID: Date?            // scrollPosition：当前顶部行/滚动目标（hour-start）
    @State private var overlap: OverlapPair?        // 编辑后检测到的重叠，弹窗让用户选择如何处理
    @State private var dayCache = DayBlocksCache()
    @State private var shareTitle = ""
    @State private var shareRows: [ShareItem] = []
    @State private var shareImage: UIImage?
    @State private var showShare = false
    @AppStorage("appColorScheme") private var colorSchemeIndex = 0
    @Environment(\.colorScheme) private var systemScheme
    private let cal = Calendar.current

    // 当前生效的明暗（跟随设置：0 系统 / 1 浅 / 2 深）
    private var effectiveScheme: ColorScheme {
        switch colorSchemeIndex { case 1: return .light; case 2: return .dark; default: return systemScheme }
    }

    private struct NewBlock: Identifiable {
        let start: Date; let end: Date
        var absorbAboveID: PersistentIdentifier? = nil   // 「新建并合并上方块」：保存时删除该上方块
        var id: Date { start }
    }
    private struct OverlapPair: Identifiable { let id = UUID(); let earlier: TimeBlock; let later: TimeBlock }
    private struct IdleRange: Hashable { let start: Date; let end: Date }
    // 块在某一天里的「片段」：跨天块裁到当天 [start,end]；底层仍是同一条 block 记录
    private struct Seg: Identifiable {
        let block: TimeBlock
        let start: Date
        let end: Date
        var id: String { "\(ObjectIdentifier(block).hashValue)@\(start.timeIntervalSinceReferenceDate)" }
    }

    // MARK: - 取数（按天 / 按 hour-start）

    private func rebuildDayCache() {
        var byDay: [Date: [TimeBlock]] = [:]
        for b in allBlocks where b.end > b.start {
            var d = cal.startOfDay(for: b.start)
            while d < b.end {            // 块覆盖的每一天都加入
                byDay[d, default: []].append(b)
                d = d.addingDays(1)
            }
        }
        dayCache.byDay = byDay
    }
    // 当天涉及的块（缓存：每个块落进它覆盖的每一天，跨天块出现在多天）
    private func dayBlocks(of day: Date) -> [TimeBlock] {
        dayCache.byDay[cal.startOfDay(for: day)] ?? []
    }
    // 当天的片段（把跨天块裁到当天，不改记录），按起点排序
    private func segs(of day: Date) -> [Seg] {
        let d0 = cal.startOfDay(for: day), d1 = d0.addingDays(1)
        return dayBlocks(of: day)
            .map { Seg(block: $0, start: max($0.start, d0), end: min($0.end, d1)) }
            .sorted { $0.start < $1.start }
    }
    // 在该整点起始的片段
    private func segsStarting(at hs: Date) -> [Seg] {
        let h = cal.component(.hour, from: hs)
        return segs(of: hs).filter { cal.component(.hour, from: $0.start) == h }
    }
    // 在更早整点起始、却延伸覆盖此整点的多小时片段 → 该整点不单独成行
    private func coveringSeg(at hs: Date) -> Seg? {
        let h = cal.component(.hour, from: hs)
        return segs(of: hs).first {
            cal.component(.hour, from: $0.start) != h && $0.start <= hs && $0.end > hs
        }
    }
    private func hourStarts(of day: Date) -> [Date] {
        let d0 = day.startOfDay
        return (0..<24).compactMap { Calendar.current.date(byAdding: .hour, value: $0, to: d0) }
    }
    private func visibleHourStarts(of day: Date) -> [Date] {
        hourStarts(of: day).filter { hs in
            if !segsStarting(at: hs).isEmpty { return true }   // 有片段起始于此 → 显示（含与前块重叠的情形）
            let he = hs.addingTimeInterval(3600)
            // 整段被多小时块覆盖且无块 → 隐藏；若覆盖块在本整点内结束（留有空闲）→ 仍显示，渲染那段空闲
            if let cov = coveringSeg(at: hs), cov.end >= he { return false }
            return true
        }
    }
    private func emptyHourStarts(of day: Date) -> [Date] {
        visibleHourStarts(of: day).filter { segsStarting(at: $0).isEmpty }
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
    // 选中的真实块（按开始时间排序），≥2 个时可合并成其中一个
    private var selectedBlocks: [TimeBlock] {
        allBlocks.filter { selected.contains($0.id) }.sorted { $0.start < $1.start }
    }
    private var canMergeBlocks: Bool { selected.count >= 2 }

    private func dayHeaderID(_ d: Date) -> String {
        "hdr-\(Int(d.startOfDay.timeIntervalSinceReferenceDate))"
    }

    // MARK: - Body

    var body: some View {
        rebuildDayCache()   // 每次渲染重建：每个块落进它覆盖的每一天（跨天块多天）
        return NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(days, id: \.self) { day in
                        dayHeader(day)
                            .background(GeometryReader { geo in
                                Color.clear.preference(key: DayFrameKey.self,
                                    value: [day: geo.frame(in: .named("timeline"))])
                            })
                        ForEach(visibleHourStarts(of: day), id: \.self) { hs in
                            hourRow(hs)
                                .id(hs)
                                .background {
                                    if selectionMode {   // 仅多选态上报行 frame（拖拽命中），普通滚动不上报
                                        GeometryReader { geo in
                                            Color.clear.preference(key: RowFrameKey.self,
                                                value: [hs: geo.frame(in: .named("timeline"))])
                                        }
                                    }
                                }
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal)
            }
            // scrollPosition 直接把目标行定位到顶部（不经过窗口顶部 → 无「滑到7天前」）
            .scrollPosition(id: $scrolledID, anchor: .top)
            .coordinateSpace(name: "timeline")
            .onPreferenceChange(RowFrameKey.self) { rowFrames = $0 }
            .onPreferenceChange(DayFrameKey.self) { dayFrames = $0; updateFocusedDay($0) }
            .highPriorityGesture(selectDragGesture)
            .onAppear { setupIfNeeded() }
            .onChange(of: goTodayTrigger) { _, _ in scrollToToday() }
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
            .confirmationDialog("合并成哪个？", isPresented: $showMergeTargetDialog, titleVisibility: .visible) {
                ForEach(selectedBlocks, id: \.id) { b in
                    Button(blockName(b)) { mergeBlocks(into: b) }
                }
                Button("不合并", role: .cancel) {}
            } message: {
                Text("将选中的块合并成一个，保留所选块的标题/分类/备注，范围覆盖全部。")
            }
            .sheet(item: $newBlock, onDismiss: afterEdit) { nb in
                let absorb = nb.absorbAboveID.flatMap { id in allBlocks.first { $0.id == id } }
                TimeBlockEditorView(start: nb.start, end: nb.end, absorbing: absorb)
            }
            .sheet(item: $editing, onDismiss: afterEdit) { TimeBlockEditorView(block: $0) }
            .confirmationDialog("时间重叠", isPresented: Binding(
                get: { overlap != nil }, set: { if !$0 { overlap = nil } }
            ), titleVisibility: .visible, presenting: overlap) { p in
                if let covered = coveredBlock(p) {   // 完全吞没：只能删除被覆盖的那个
                    Button("修改并删除「\(blockName(covered))」", role: .destructive) { resolveDeleteCovered(covered) }
                } else {                              // 部分重叠：两块相接即可
                    Button("同步修改开始和结束时间") { resolveSync(p) }
                }
                Button("撤销修改", role: .cancel) { ctx.undoManager?.undo(); overlap = nil }
            } message: { p in
                Text("「\(blockName(p.earlier))」(到 \(clock(p.earlier.end))) 与「\(blockName(p.later))」(\(clock(p.later.start)) 起) 重叠。")
            }
            .sheet(isPresented: $showDatePicker) {
                NavigationStack {
                    VStack {
                        DatePicker("跳转到", selection: $datePickerDay, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                            .padding()
                            .onChange(of: datePickerDay) { _, d in   // 选中即跳转
                                showDatePicker = false; goToDay(d)
                            }
                        Spacer()
                    }
                    .navigationTitle("选择日期")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("今天") { datePickerDay = .now }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showShare) {
                SharePreviewSheet(image: shareImage, title: shareTitle, items: shareRows,
                                  scheme: effectiveScheme)
            }
        }
    }

    // 所有改动后的统一收尾：合并相邻同类块（跨天不拆，保留单条记录、视觉再裁两段）
    private func normalize() {
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
            if a.end > b.start {   // 重叠（跨天也算）
                if sameKind(a, b) { continue }   // 同类同标题同备注：会被 coalesce 合并，不弹窗
                overlap = OverlapPair(earlier: a, later: b)
                return
            }
        }
    }

    private func blockName(_ b: TimeBlock) -> String {
        b.title.isEmpty ? catStyle(for: b.category, custom: customCats).name : b.title
    }

    // 一方完全吞没另一方时，返回被覆盖（区间被完全包含）的那个块；否则 nil（部分重叠）
    private func coveredBlock(_ p: OverlapPair) -> TimeBlock? {
        if p.earlier.start <= p.later.start && p.earlier.end >= p.later.end { return p.later }
        if p.later.start <= p.earlier.start && p.later.end >= p.earlier.end { return p.earlier }
        return nil
    }

    // 部分重叠：把前块结束 + 后块开始一起挪到重叠区间的中点，两块刚好相接、不再重叠
    private func resolveSync(_ p: OverlapPair) {
        let lo = p.later.start, hi = p.earlier.end
        let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
        p.earlier.end = mid
        p.later.start = mid
        overlap = nil
        afterEdit()   // 继续规整并检测下一处重叠
    }

    // 完全吞没：删除被覆盖的块，保留吞没它的块
    private func resolveDeleteCovered(_ covered: TimeBlock) {
        ctx.delete(covered)
        overlap = nil
        afterEdit()
    }

    // MARK: - 天头（白线分割 + 日期 + 当天小结）

    private func dayHeader(_ day: Date) -> some View {
        let segList = segs(of: day)   // 当天片段（跨天块按当天部分计）
        let total = segList.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        let blocks = segList
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
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { shareScreenshot() } label: { Image(systemName: "square.and.arrow.up") }
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
                        Button { setStartNow(b); exitSelection() } label: { Image(systemName: "arrow.left.to.line") }
                    }
                    if Date.now > b.start {   // 结束改为现在
                        Spacer()
                        Button { setEndNow(b); exitSelection() } label: { Image(systemName: "arrow.right.to.line") }
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
                if canMergeBlocks {   // 选中多个块 → 合并成其中一个
                    Spacer()
                    Button { showMergeTargetDialog = true } label: {
                        Label("合并", systemImage: "arrow.triangle.merge")
                    }
                }
                Spacer()
                Button(role: .destructive) { deleteSelected() } label: {
                    Label("删除\(selected.isEmpty ? "" : " \(selected.count)")", systemImage: "trash")
                }
                .disabled(selected.isEmpty)
            }
        } else {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                Button { ctx.undoManager?.undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!(ctx.undoManager?.canUndo ?? false))
                Button { ctx.undoManager?.redo() } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!(ctx.undoManager?.canRedo ?? false))
            }
            ToolbarItem(placement: .principal) { dayNav }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { shareScreenshot() } label: { Image(systemName: "square.and.arrow.up") }
                Button("选择") { selectionMode = true }
            }
        }
    }

    // 把焦点天的日程渲染成图（剪到首块…末块，下方全是空闲不进图；整天无块则不分享）
    private func shareScreenshot() {
        let data = shareItems()
        guard !data.items.isEmpty else { return }
        shareTitle = data.title
        shareRows = data.items
        shareImage = nil
        showShare = true   // 先弹（转圈），随后渲染默认图（无标题）
        DispatchQueue.main.async {
            let r = ImageRenderer(content:
                DayShareView(title: shareTitle, items: shareRows, showTitle: false)
                    .environment(\.colorScheme, effectiveScheme))
            r.scale = 2
            shareImage = r.uiImage
        }
    }

    // 当前屏幕里可见的天（按 header 在视口中的位置；含被上方块覆盖到顶部的那天）
    private func visibleDays() -> [Date] {
        let vh = UIScreen.main.bounds.height
        var result: [Date] = []
        for (i, d) in days.enumerated() {
            guard let top = dayFrames[d]?.minY else { continue }
            let bottom = (i + 1 < days.count ? dayFrames[days[i + 1]]?.minY : nil) ?? .greatestFiniteMagnitude
            if top < vh && bottom > 0 { result.append(d) }   // 该天区段与视口相交
        }
        return result
    }

    private func shareRow(_ item: HourItem) -> ShareItem {
        switch item {
        case .block(let seg):
            let b = seg.block
            let s = catStyle(for: b.category, custom: customCats)
            return ShareItem(time: clock(seg.start), name: s.name, title: b.title, note: b.note,
                             sub: "\(clock(seg.start))-\(clock(seg.end)) · \(formatDuration(seg.end.timeIntervalSince(seg.start)))",
                             color: s.color)
        case .idle(let st, let e):
            return ShareItem(time: clock(st), name: "空闲", sub: formatDuration(e.timeIntervalSince(st)), color: nil)
        case .empty(let hs):
            return ShareItem(time: clock(hs), name: "空闲", sub: "1小时", color: nil)
        }
    }

    // 分享范围：从可视顶部那行的时间（scrolledID）起，覆盖可视的若干天
    private func shareRange() -> (topHS: Date, days: [Date]) {
        let topHS = scrolledID ?? cal.startOfDay(for: focusedDay)
        let startDay = cal.startOfDay(for: topHS)
        let lastVisible = visibleDays().last ?? startDay.addingDays(1)   // dayFrames 未就绪时至少含次日
        let endDay = min(max(lastVisible, startDay), startDay.addingDays(6))   // 上限一周
        var ds: [Date] = []; var d = startDay
        while d <= endDay { ds.append(d); d = d.addingDays(1) }
        return (topHS, ds)
    }

    // 从可视顶部时间往后：第一天从该时间起，后续天整天；每天首块…末块、丢前后空闲、空天跳过
    private func shareItems() -> (title: String, items: [ShareItem]) {
        func isBlock(_ i: HourItem) -> Bool { if case .block = i { return true }; return false }
        let (topHS, ds) = shareRange()
        var out: [ShareItem] = []
        for day in ds {
            var hours = visibleHourStarts(of: day)
            if cal.isDate(day, inSameDayAs: topHS) { hours = hours.filter { $0 >= topHS } }   // 第一天从可视顶部起
            let raw = hours.flatMap { hourItems($0) }
            guard let f = raw.firstIndex(where: isBlock), let l = raw.lastIndex(where: isBlock) else { continue }
            out.append(ShareItem(dayHeader: day.isSameDay(as: .now) ? "今天 · \(day.dayTitle)" : day.dayTitle))
            for item in raw[f...l] { out.append(shareRow(item)) }
        }
        return ("三省小记 · 时间轴", out)
    }

    // MARK: - 行

    // 一个整点里按时间顺序排出的条目：空整点槽 / 块 / 块之间的空闲段（任意长度都显示）
    private enum HourItem: Identifiable {
        case empty(Date)            // 整点空闲槽（可多选/填充）
        case block(Seg)             // 块片段（跨天块裁到当天）
        case idle(Date, Date)       // 块之间剩余的空闲（展示 + 点按建块）
        var id: String {
            switch self {
            case .empty(let d): return "e\(d.timeIntervalSinceReferenceDate)"
            case .block(let seg): return "b\(seg.id)"
            case .idle(let s, _): return "i\(s.timeIntervalSinceReferenceDate)"
            }
        }
    }

    private func hourItems(_ hs: Date) -> [HourItem] {
        let he = hs.addingTimeInterval(3600)
        let starting = segsStarting(at: hs).sorted { $0.start < $1.start }
        let cov = coveringSeg(at: hs)
        // 游标从整点起；若被前一个多小时片段占用了开头，跳到它的结束（那段不算空闲）
        var cursor = hs
        if let cov { cursor = min(he, max(cursor, cov.end)) }

        if starting.isEmpty {
            if cov == nil { return [.empty(hs)] }              // 完全空 → 整点空闲槽
            return cursor < he ? [.idle(cursor, he)] : []      // 覆盖片段在本整点内结束 → 渲染剩余空闲
        }

        var items: [HourItem] = []
        for seg in starting {
            if seg.start > cursor { items.append(.idle(cursor, seg.start)) }   // 片段前空闲
            items.append(.block(seg))
            cursor = max(cursor, seg.end)
        }
        if cursor < he { items.append(.idle(cursor, he)) }                 // 片段后到整点末的空闲
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
            // 空整点也是空闲：左侧时间同样给「合并到上/下方」菜单
            timeLabeledRow(leading: {
                leadingTimeMenu(hs, isNow: isNowIn(hs, hs.addingTimeInterval(3600))) {
                    idleTimeMenu(hs, hs.addingTimeInterval(3600))
                }
            }) {
                emptySlot(hs)
            }
        case .block(let seg):
            timeLabeledRow(leading: {
                leadingTimeMenu(seg.start, isNow: isNowIn(seg.start, seg.end)) { blockTimeMenu(seg.block) }
            }) {
                Button { tapBlock(seg.block) } label: { blockCard(seg) }.buttonStyle(.plain)
            }
        case .idle(let s, let e):
            timeLabeledRow(leading: {
                leadingTimeMenu(s, isNow: isNowIn(s, e)) { idleTimeMenu(s, e) }
            }) {
                idleGap(s, e)
            }
        }
    }

    private func timeText(_ time: Date, isNow: Bool) -> some View {
        Text(clock(time))
            .font(.caption).monospacedDigit()
            .fontWeight(isNow ? .bold : .regular)
            .underline(isNow, color: .accentColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(isNow ? Color.accentColor : .secondary)
    }

    // 左侧时间列（普通态，无菜单）：撑满整行高度
    private func plainLeading(_ time: Date, isNow: Bool) -> some View {
        timeText(time, isNow: isNow)
            .frame(minWidth: 44, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 8)
    }

    // 左侧时间列做菜单触发：触发区 = 时间 + 下方空白（整个 block 左侧）。多选态退回纯文字。
    @ViewBuilder
    private func leadingTimeMenu<M: View>(_ time: Date, isNow: Bool, @ViewBuilder menu: () -> M) -> some View {
        if selectionMode {
            plainLeading(time, isNow: isNow)
        } else {
            Menu { menu() } label: {
                timeText(time, isNow: isNow)
                    .frame(minWidth: 44, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 8)
                    .contentShape(Rectangle())
            }
        }
    }

    // 块左侧时间菜单
    @ViewBuilder
    private func blockTimeMenu(_ b: TimeBlock) -> some View {
        if hasGapBefore(b) {
            Button { mergeGapBefore(b) } label: { Label("合并上方空闲", systemImage: "arrow.up.to.line") }
        }
        if hasGapAfter(b) {
            Button { mergeGapAfter(b) } label: { Label("合并下方空闲", systemImage: "arrow.down.to.line") }
        }
        if Date.now < b.end {
            Button { setStartNow(b) } label: { Label("现在开始", systemImage: "arrow.left.to.line") }
        }
        if Date.now > b.start {
            Button { setEndNow(b) } label: { Label("现在结束", systemImage: "arrow.right.to.line") }
        }
    }

    // 空闲段左侧时间菜单：合并到上/下方块（跨过连续空闲，并入最近的真实块）
    @ViewBuilder
    private func idleTimeMenu(_ s: Date, _ e: Date) -> some View {
        if let p = blockAbove(s) {
            Button { p.end = max(p.end, e); afterEdit() } label: { Label("合并到上方", systemImage: "arrow.up.to.line") }
        }
        if let n = blockBelow(e) {
            Button { n.start = min(n.start, s); afterEdit() } label: { Label("合并到下方", systemImage: "arrow.down.to.line") }
        }
        Button { newBlock = NewBlock(start: s, end: e) } label: { Label("新建块", systemImage: "plus") }
        if let p = blockAbove(s) {   // 新建块覆盖「上方块起点…本空闲末」，保存后吃掉上方块
            Button { newBlock = NewBlock(start: p.start, end: e, absorbAboveID: p.id) } label: {
                Label("新建并合并上方块", systemImage: "plus.square.on.square")
            }
        }
    }
    // 此空闲上方最近的块（结束 ≤ s，取最晚结束）；中间只会是连续空闲，合并即吃掉它们
    private func blockAbove(_ s: Date) -> TimeBlock? {
        allBlocks.filter { $0.start.isSameDay(as: s) && $0.end <= s }.max { $0.end < $1.end }
    }
    // 此空闲下方最近的块（开始 ≥ e，取最早开始）
    private func blockBelow(_ e: Date) -> TimeBlock? {
        allBlocks.filter { $0.start.isSameDay(as: e) && $0.start >= e }.min { $0.start < $1.start }
    }

    private func timeLabeledRow<L: View, C: View>(@ViewBuilder leading: () -> L,
                                                  @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 10) {
            leading()
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

    private func blockCard(_ seg: Seg) -> some View {
        let b = seg.block
        let isSel = selected.contains(b.id)
        let s = catStyle(for: b.category, custom: customCats)
        let range = "\(seg.start.hm)-\(seg.end.hm) · \(formatDuration(seg.end.timeIntervalSince(seg.start)))"
        return HStack(spacing: 10) {
            if selectionMode {
                Image(systemName: isSel ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSel ? Color.accentColor : .secondary)
            }
            RoundedRectangle(cornerRadius: 3).fill(s.color).frame(width: 5)
            VStack(alignment: .leading, spacing: 3) {
                if b.title.isEmpty {
                    // 无标题：上行 图标+分类，下行 时间范围·时长
                    Label(s.name, systemImage: s.icon).font(.subheadline).foregroundStyle(s.color)
                    Text(range).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    // 有标题：图标 分类 · 标题 （备注），下行 时间范围·时长
                    HStack(spacing: 6) {
                        Label(s.name, systemImage: s.icon).font(.subheadline).foregroundStyle(s.color)
                        Text(b.note.isEmpty ? "· \(b.title)" : "· \(b.title)（\(b.note)）")
                            .font(.subheadline).lineLimit(1)
                    }
                    Text(range).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
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
            Button { datePickerDay = focusedDay; showDatePicker = true } label: {   // 点日期 → 选日期
                Text(focusedDay.isSameDay(as: .now) ? "今天" : focusedDay.monthDay)
                    .font(.subheadline).bold().lineLimit(1).fixedSize()
            }
            .buttonStyle(.plain)
            Button { goToDay(focusedDay.addingDays(1)) } label: { Image(systemName: "chevron.right") }
        }
    }

    // MARK: - 窗口 / 滚动

    // 窗口跨度：以中心天为基准前后各 windowRadius 天（预加载前后 7 天；更远由 goToDay 重建窗口）
    private static let windowRadius = 7

    private func setupIfNeeded() {
        guard days.isEmpty else { return }
        let t = Date.now.startOfDay
        days = (-Self.windowRadius...Self.windowRadius).map { t.addingDays($0) }
        focusedDay = t
        scrolledID = firstFreeHourStart() ?? visibleHourStarts(of: t).first   // 首屏直接定位（scrollPosition）
    }

    // 点「时间轴」Tab：定位今天「当前第一个空闲」行。用 scrollPosition 直接落位，不经过窗口顶部。
    private func scrollToToday() {
        let t = Date.now.startOfDay
        if t < (days.first ?? t) || t > (days.last ?? t) {   // 目标在窗口外 → 以今天为中心重建
            days = (-Self.windowRadius...Self.windowRadius).map { t.addingDays($0) }
        }
        focusedDay = t
        let target = firstFreeHourStart() ?? visibleHourStarts(of: t).first
        DispatchQueue.main.async { scrolledID = target }   // 让窗口/行先就绪再定位
    }

    // 今天从当前钟点起、第一个含空闲（空整点或小空闲段）的行
    private func firstFreeHourStart() -> Date? {
        let t = Date.now.startOfDay
        guard t.isSameDay(as: .now) else { return visibleHourStarts(of: t).first }
        let now = Date.now
        for hs in visibleHourStarts(of: t) where hs.addingTimeInterval(3600) > now {
            let hasFree = hourItems(hs).contains {
                switch $0 { case .empty, .idle: return true; case .block: return false }
            }
            if hasFree { return hs }
        }
        return visibleHourStarts(of: t).last
    }

    // 焦点天 = 已滚过顶部、header 最靠近顶部的那天（按天 header frame，便宜）
    private func updateFocusedDay(_ dayFrames: [Date: CGRect]) {
        let above = dayFrames.filter { $0.value.minY <= 44 }
        let pick = above.max { $0.value.minY < $1.value.minY }?.key
            ?? dayFrames.min { $0.value.minY < $1.value.minY }?.key
        if let d = pick, d != focusedDay { focusedDay = d }
    }

    private func goToDay(_ day: Date) {
        let d = day.startOfDay
        // 目标接近/超出窗口边缘 → 以它为中心重建窗口（即可继续往更早/更晚浏览）
        let nearEdge = d <= (days.first ?? d).addingDays(2) || d >= (days.last ?? d).addingDays(-2)
        if nearEdge {
            days = (-Self.windowRadius...Self.windowRadius).map { d.addingDays($0) }
        }
        focusedDay = d
        let target = (d.isSameDay(as: .now) ? firstFreeHourStart() : nil) ?? visibleHourStarts(of: d).first
        DispatchQueue.main.async { scrolledID = target }
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
                case .block(let seg): ids.insert(seg.block.id)
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

    // 把所有选中块合并成 target：target 拉长覆盖全部选中块（及选中空闲）的范围，其余块删除
    private func mergeBlocks(into target: TimeBlock) {
        var lo = target.start, hi = target.end
        for b in selectedBlocks { lo = min(lo, b.start); hi = max(hi, b.end) }
        for hs in selectedHourStarts { lo = min(lo, hs); hi = max(hi, hs.addingTimeInterval(3600)) }
        for r in selectedIdle { lo = min(lo, r.start); hi = max(hi, r.end) }
        target.start = lo; target.end = hi
        for b in selectedBlocks where b.id != target.id { ctx.delete(b) }
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

    // 相邻且同类同名的块自动并成一条（跨天也合并——保留单条记录，视觉再裁两段）
    // 同类 + 同标题 + 同备注，视为同一件事：相邻/重叠就自动合并（不弹「时间重叠」）
    private func sameKind(_ a: TimeBlock, _ b: TimeBlock) -> Bool {
        a.category == b.category && a.title == b.title && a.note == b.note
    }

    private func coalesceAdjacent() {
        let sorted = allBlocks.sorted { $0.start < $1.start }
        var prev: TimeBlock?
        for b in sorted {
            if let p = prev, sameKind(p, b), b.start <= p.end {
                p.end = max(p.end, b.end)
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

}
