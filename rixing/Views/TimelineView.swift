// Views/TimelineView.swift — 今日：默认按整点切成 24 个 1 小时块；支持多选批量删除
import SwiftUI
import SwiftData

struct TimelineView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \TimeBlock.start, order: .forward) private var allBlocks: [TimeBlock]

    @State private var selectedDay: Date = .now
    @State private var editing: TimeBlock?      // 点击已有块进入编辑
    @State private var newBlock: NewBlock?      // 点击空槽：在该整点新建
    @State private var selectionMode = false    // 多选模式
    @State private var selected: Set<PersistentIdentifier> = []

    private struct NewBlock: Identifiable { let hour: Int; var id: Int { hour } }

    private var dayBlocks: [TimeBlock] {
        allBlocks.filter { $0.start.isSameDay(as: selectedDay) }
    }
    private var totalTracked: TimeInterval {
        dayBlocks.reduce(0) { $0 + $1.duration }
    }
    private func blocks(inHour h: Int) -> [TimeBlock] {
        dayBlocks.filter { Calendar.current.component(.hour, from: $0.start) == h }
    }
    private var nowHour: Int { Calendar.current.component(.hour, from: .now) }
    private var allSelected: Bool { !dayBlocks.isEmpty && selected.count == dayBlocks.count }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        ForEach(0..<24, id: \.self) { h in
                            hourRow(h).id(h)
                        }
                    } header: {
                        Text("已记录 \(formatDuration(totalTracked)) · 共 \(dayBlocks.count) 块")
                    }
                }
                .listStyle(.plain)
                .onAppear {
                    if selectedDay.isSameDay(as: .now) {
                        proxy.scrollTo(max(0, nowHour - 1), anchor: .top)
                    }
                }
            }
            .navigationTitle(selectionMode ? "已选 \(selected.count)" : "今日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(item: $newBlock) { TimeBlockEditorView(day: selectedDay, hour: $0.hour) }
            .sheet(item: $editing) { TimeBlockEditorView(block: $0) }
        }
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
            ToolbarItem(placement: .bottomBar) {
                Button(role: .destructive) { deleteSelected() } label: {
                    Label("删除\(selected.isEmpty ? "" : " \(selected.count)")", systemImage: "trash")
                }
                .disabled(selected.isEmpty)
            }
        } else {
            ToolbarItem(placement: .principal) { dayNav }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("选择") { selectionMode = true }.disabled(dayBlocks.isEmpty)
            }
        }
    }

    // 单个整点行：左侧钟点（保证单行）+ 右侧块（有则展示，无则空槽可点）
    private func hourRow(_ h: Int) -> some View {
        let items = blocks(inHour: h)
        let isNow = selectedDay.isSameDay(as: .now) && h == nowHour
        return HStack(alignment: .top, spacing: 10) {
            Text(String(format: "%02d:00", h))
                .font(.caption).monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)   // 任意字体大小都单行不换行/不截断
                .foregroundStyle(isNow ? Color.accentColor : .secondary)
                .frame(minWidth: 44, alignment: .leading)
                .padding(.top, 8)

            if items.isEmpty {
                Button { if !selectionMode { newBlock = NewBlock(hour: h) } } label: {
                    HStack {
                        Text("空闲").font(.subheadline).foregroundStyle(.tertiary)
                        Spacer()
                        if !selectionMode { Image(systemName: "plus").font(.caption).foregroundStyle(.tertiary) }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(selectionMode)
            } else {
                VStack(spacing: 6) {
                    ForEach(items) { b in
                        Button { tapBlock(b) } label: { blockCard(b) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .listRowSeparator(.hidden)
        .padding(.vertical, 2)
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

    // 日期切换：前一天 / 今天 / 后一天
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

    // MARK: - 多选操作

    private func tapBlock(_ b: TimeBlock) {
        if selectionMode {
            if selected.contains(b.id) { selected.remove(b.id) } else { selected.insert(b.id) }
        } else {
            editing = b
        }
    }
    private func toggleSelectAll() {
        if allSelected { selected.removeAll() } else { selected = Set(dayBlocks.map { $0.id }) }
    }
    private func exitSelection() {
        selectionMode = false; selected.removeAll()
    }
    private func deleteSelected() {
        for b in dayBlocks where selected.contains(b.id) { ctx.delete(b) }
        exitSelection()
    }
}
