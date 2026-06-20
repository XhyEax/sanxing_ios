// Views/DiaryView.swift — 日记：按天分组，倒序展示
import SwiftUI
import SwiftData

struct DiaryView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \DiaryEntry.createdAt, order: .reverse) private var entries: [DiaryEntry]

    @State private var editing: DiaryEntry?
    @State private var showNew = false

    // 按自然日分组，日期倒序
    private var groups: [(day: Date, items: [DiaryEntry])] {
        let dict = Dictionary(grouping: entries) { $0.createdAt.startOfDay }
        return dict.keys.sorted(by: >).map { (day: $0, items: dict[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView("还没有日记",
                        systemImage: "book.closed",
                        description: Text("点右上角 ＋ 写下今天"))
                } else {
                    List {
                        ForEach(groups, id: \.day) { group in
                            Section(group.day.dayTitle) {
                                ForEach(group.items) { entry in
                                    Button { editing = entry } label: { row(entry) }
                                        .buttonStyle(.plain)
                                }
                                .onDelete { deleteIn(group.items, $0) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("日记")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showNew) { DiaryEditorView() }
            .sheet(item: $editing) { DiaryEditorView(entry: $0) }
        }
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
