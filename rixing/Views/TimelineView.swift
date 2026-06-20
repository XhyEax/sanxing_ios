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

    @State private var selectedDay: Date = .now
    @State private var editing: TimeBlock?
    @State private var newBlock: NewBlock?
    @State private var selectionMode = false
    @State private var selected: Set<PersistentIdentifier> = []   // 选中的已有块
    @State private var selectedHours: Set<Int> = []               // 选中的空闲整点
    @State private var showFillDialog = false

    @State private var rowFrames: [Int: CGRect] = [:]
    @State private var dragAnchorHour: Int?

    private struct NewBlock: Identifiable { let hour: Int; var id: Int { hour } }

    private var dayBlocks: [TimeBlock] {
        allBlocks.filter { $0.start.isSameDay(as: selectedDay) }
    }
    private var totalTracked: TimeInterval { dayBlocks.reduce(0) { $0 + $1.duration } }
    private func blocks(inHour h: Int) -> [TimeBlock] {
        dayBlocks.filter { Calendar.current.component(.hour, from: $0.start) == h }
    }
    private var emptyHours: [Int] { (0..<24).filter { blocks(inHour: $0).isEmpty } }
    private var nowHour: Int { Calendar.current.component(.hour, from: .now) }
    private var totalSelected: Int { selected.count + selectedHours.count }
    private var allSelected: Bool {
        let n = dayBlocks.count + emptyHours.count
        return n > 0 && selected.count == dayBlocks.count && selectedHours.count == emptyHours.count
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        header
                        ForEach(0..<24, id: \.self) { h in
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
            .confirmationDialog("填充为", isPresented: $showFillDialog, titleVisibility: .visible) {
                ForEach(BlockCategory.allCases) { c in
                    Button(c.name) { fillSelectedHours(with: c) }
                }
                Button("取消", role: .cancel) {}
            }
            .sheet(item: $newBlock) { TimeBlockEditorView(day: selectedDay, hour: $0.hour) }
            .sheet(item: $editing) { TimeBlockEditorView(block: $0) }
        }
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
                Button(role: .destructive) { deleteSelected() } label: {
                    Label("删除\(selected.isEmpty ? "" : " \(selected.count)")", systemImage: "trash")
                }
                .disabled(selected.isEmpty)
            }
        } else {
            ToolbarItem(placement: .principal) { dayNav }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("选择") { selectionMode = true }
            }
        }
    }

    // 单个整点行
    private func hourRow(_ h: Int) -> some View {
        let items = blocks(inHour: h)
        let isNow = selectedDay.isSameDay(as: .now) && h == nowHour
        return HStack(alignment: .top, spacing: 10) {
            Text(String(format: "%02d:00", h))
                .font(.caption).monospacedDigit()
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
        return HStack(spacing: 10) {
            if selectionMode {
                Image(systemName: isSel ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSel ? Color.accentColor : .secondary)
            }
            RoundedRectangle(cornerRadius: 3).fill(b.cat.color).frame(width: 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(b.title.isEmpty ? b.cat.name : b.title).font(.subheadline)
                HStack(spacing: 6) {
                    Label(b.cat.name, systemImage: b.cat.icon).font(.caption2).foregroundStyle(b.cat.color)
                    Text("· \(b.start.hm)-\(b.end.hm) · \(formatDuration(b.duration))")
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background((isSel ? b.cat.color.opacity(0.20) : b.cat.color.opacity(0.10)),
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
            let items = blocks(inHour: h)
            if items.isEmpty { hours.insert(h) } else { blockIDs.formUnion(items.map { $0.id }) }
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
        if allSelected {
            selected.removeAll(); selectedHours.removeAll()
        } else {
            selected = Set(dayBlocks.map { $0.id }); selectedHours = Set(emptyHours)
        }
    }
    private func exitSelection() {
        selectionMode = false; selected.removeAll(); selectedHours.removeAll(); dragAnchorHour = nil
    }
    private func deleteSelected() {
        for b in dayBlocks where selected.contains(b.id) { ctx.delete(b) }
        exitSelection()
    }
    private func fillSelectedHours(with cat: BlockCategory) {
        let cal = Calendar.current
        for h in selectedHours {
            let start = cal.date(bySettingHour: h, minute: 0, second: 0, of: selectedDay.startOfDay)
                ?? selectedDay.startOfDay
            ctx.insert(TimeBlock(start: start, end: start.addingTimeInterval(3600),
                                 title: "", category: cat.rawValue))
        }
        exitSelection()
    }
}
