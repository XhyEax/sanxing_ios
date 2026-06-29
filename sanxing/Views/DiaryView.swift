// Views/DiaryView.swift — 随手记：按天分组，倒序展示；顶部日期导航（仅可跳到有记录的日期）
import SwiftUI
import SwiftData
import UIKit

// 各天 section header 在列表坐标系里的位置，用于跟踪顶部当前天
private struct DiaryDayFrameKey: PreferenceKey {
    static var defaultValue: [Date: CGRect] = [:]
    static func reduce(value: inout [Date: CGRect], nextValue: () -> [Date: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct DiaryView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \DiaryEntry.createdAt, order: .reverse) private var entries: [DiaryEntry]

    @State private var editing: DiaryEntry?
    @State private var showNew = false
    @State private var focusedDay = Date.now.startOfDay   // 顶部导航当前天
    @State private var showDatePicker = false
    @State private var datePickerDay = Date.now
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var searchEditing: DiaryEntry?

    // 按自然日分组，日期倒序
    private var groups: [(day: Date, items: [DiaryEntry])] {
        let dict = Dictionary(grouping: entries) { $0.createdAt.startOfDay }
        return dict.keys.sorted(by: >).map { (day: $0, items: dict[$0] ?? []) }
    }
    // 有记录的日期（升序）
    private var entryDays: [Date] { groups.map(\.day).sorted() }
    private var prevEntryDay: Date? { entryDays.last { $0 < focusedDay } }   // 更早一天
    private var nextEntryDay: Date? { entryDays.first { $0 > focusedDay } }  // 更晚一天

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Group {
                    if entries.isEmpty {
                        ContentUnavailableView("还没有日记",
                            systemImage: "book.closed",
                            description: Text("点右上角 ＋ 写下今天"))
                    } else {
                        List {
                            ForEach(groups, id: \.day) { group in
                                Section {
                                    ForEach(group.items) { entry in
                                        Button { editing = entry } label: { row(entry) }
                                            .buttonStyle(.plain)
                                            .contextMenu {
                                                Button {
                                                    UIPasteboard.general.string = entry.text
                                                } label: { Label("复制", systemImage: "doc.on.doc") }
                                                .disabled(entry.text.isEmpty)
                                            }
                                    }
                                    .onDelete { deleteIn(group.items, $0) }
                                } header: {
                                    Text(group.day.dayTitle)
                                        .background(GeometryReader { geo in
                                            Color.clear.preference(key: DiaryDayFrameKey.self,
                                                value: [group.day: geo.frame(in: .named("diary"))])
                                        })
                                }
                                .id(group.day)
                            }
                        }
                        .coordinateSpace(name: "diary")
                        .onPreferenceChange(DiaryDayFrameKey.self) { updateFocusedDay($0) }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !entries.isEmpty {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                        }
                        ToolbarItem(placement: .principal) { dayNav(proxy) }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showNew = true } label: { Image(systemName: "plus") }
                    }
                }
                .sheet(isPresented: $showDatePicker) {
                    NavigationStack {
                        VStack {
                            DatePicker("跳转到", selection: $datePickerDay,
                                       in: (entryDays.first ?? .now)...(entryDays.last ?? .now),
                                       displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .environment(\.locale, Locale(identifier: "zh_CN"))
                                .padding()
                                .onChange(of: datePickerDay) { _, d in   // 选中即跳到最近的有记录日期
                                    showDatePicker = false
                                    if let day = nearestEntryDay(to: d) { goTo(day, proxy) }
                                }
                            Spacer()
                        }
                        .navigationTitle("跳转到有记录的日期")
                        .navigationBarTitleDisplayMode(.inline)
                    }
                    .presentationDetents([.medium, .large])
                }
                .onAppear { if let newest = entryDays.last { focusedDay = newest } }
            }
            .sheet(isPresented: $showNew) { DiaryEditorView() }
            .sheet(item: $editing) { DiaryEditorView(entry: $0) }
            .sheet(isPresented: $showSearch) { searchSheet }
        }
    }

    // 搜索日记正文
    private var searchResults: [DiaryEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(q) }   // entries 已按时间倒序
    }

    private var searchSheet: some View {
        NavigationStack {
            Group {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("搜索日记", systemImage: "magnifyingglass",
                        description: Text("输入关键词查找正文"))
                } else if searchResults.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(searchResults) { e in
                        Button { searchEditing = e } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(e.createdAt.dayTitle + " " + e.createdAt.hm)
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(e.text).font(.body).lineLimit(3)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { showSearch = false } }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "搜索日记内容")
            .sheet(item: $searchEditing) { DiaryEditorView(entry: $0) }
        }
    }

    // 顶部日期导航：‹ 焦点天 ›，中间点击选有记录的日期（同时间轴）
    private func dayNav(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 12) {
            Button { if let p = prevEntryDay { goTo(p, proxy) } } label: { Image(systemName: "chevron.left") }
                .disabled(prevEntryDay == nil)
            Button { datePickerDay = focusedDay; showDatePicker = true } label: {
                Text(focusedDay.isSameDay(as: .now) ? "今天" : focusedDay.monthDay)
                    .font(.subheadline).bold().lineLimit(1).fixedSize()
            }
            .buttonStyle(.plain)
            Button { if let n = nextEntryDay { goTo(n, proxy) } } label: { Image(systemName: "chevron.right") }
                .disabled(nextEntryDay == nil)
        }
    }

    private func goTo(_ day: Date, _ proxy: ScrollViewProxy) {
        focusedDay = day
        withAnimation { proxy.scrollTo(day, anchor: .top) }
    }

    // 顶部当前天：贴近列表顶部的那天 header（同时间轴），随手滑动实时更新
    private func updateFocusedDay(_ frames: [Date: CGRect]) {
        let above = frames.filter { $0.value.minY <= 44 }
        let pick = above.max { $0.value.minY < $1.value.minY }?.key
            ?? frames.min { $0.value.minY < $1.value.minY }?.key
        if let d = pick, d != focusedDay { focusedDay = d }
    }
    // 离目标最近的有记录日期
    private func nearestEntryDay(to d: Date) -> Date? {
        let t = d.startOfDay
        return entryDays.min { abs($0.timeIntervalSince(t)) < abs($1.timeIntervalSince(t)) }
    }

    private func row(_ e: DiaryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(e.createdAt.hm)
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)   // 与「今日」一致：任意字号都完整单行
                .frame(minWidth: 44, alignment: .leading)
            if !Mood.emoji(e.mood).isEmpty {
                Text(Mood.emoji(e.mood))
            }
            Text(e.text.isEmpty ? "（空）" : e.text)
                .font(.body)
                .foregroundStyle(e.text.isEmpty ? .secondary : .primary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func deleteIn(_ items: [DiaryEntry], _ offsets: IndexSet) {
        for i in offsets { ctx.delete(items[i]) }
    }
}
