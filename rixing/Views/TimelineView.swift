// Views/TimelineView.swift — 今日时间轴：按起始时间排列当天时间块
import SwiftUI
import SwiftData

struct TimelineView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \TimeBlock.start, order: .forward) private var allBlocks: [TimeBlock]

    @State private var selectedDay: Date = .now
    @State private var editing: TimeBlock?      // 点击已有块进入编辑
    @State private var showNew = false

    private var dayBlocks: [TimeBlock] {
        allBlocks.filter { $0.start.isSameDay(as: selectedDay) }
    }
    private var totalTracked: TimeInterval {
        dayBlocks.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        NavigationStack {
            Group {
                if dayBlocks.isEmpty {
                    ContentUnavailableView("还没有时间块",
                        systemImage: "clock.badge.questionmark",
                        description: Text("点右上角 ＋ 记录或安排一段时间"))
                } else {
                    List {
                        Section {
                            ForEach(dayBlocks) { block in
                                Button { editing = block } label: { blockRow(block) }
                                    .buttonStyle(.plain)
                            }
                            .onDelete(perform: deleteBlocks)
                        } header: {
                            Text("已记录 \(formatDuration(totalTracked))")
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("今日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { dayNav }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showNew) {
                TimeBlockEditorView(day: selectedDay)
            }
            .sheet(item: $editing) { block in
                TimeBlockEditorView(block: block)
            }
        }
    }

    // 日期切换：前一天 / 今天 / 后一天
    private var dayNav: some View {
        HStack(spacing: 12) {
            Button { selectedDay = selectedDay.addingDays(-1) } label: {
                Image(systemName: "chevron.left")
            }
            Button {
                selectedDay = .now
            } label: {
                Text(selectedDay.isSameDay(as: .now) ? "今天" : selectedDay.dayTitle)
                    .font(.subheadline).bold()
            }
            .buttonStyle(.plain)
            Button { selectedDay = selectedDay.addingDays(1) } label: {
                Image(systemName: "chevron.right")
            }
        }
    }

    private func blockRow(_ b: TimeBlock) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(b.start.hm).font(.subheadline).monospacedDigit()
                Text(b.end.hm).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 52, alignment: .trailing)

            RoundedRectangle(cornerRadius: 3)
                .fill(b.cat.color)
                .frame(width: 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(b.title.isEmpty ? b.cat.name : b.title)
                    .font(.body)
                HStack(spacing: 6) {
                    Label(b.cat.name, systemImage: b.cat.icon)
                        .font(.caption2).foregroundStyle(b.cat.color)
                    Text("· \(formatDuration(b.duration))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func deleteBlocks(_ offsets: IndexSet) {
        for i in offsets { ctx.delete(dayBlocks[i]) }
    }
}
