// Views/TimelineView.swift — 今日：默认把一天切成 24 个整点时间块，点空槽填写、点已有块编辑
import SwiftUI
import SwiftData

struct TimelineView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \TimeBlock.start, order: .forward) private var allBlocks: [TimeBlock]

    @State private var selectedDay: Date = .now
    @State private var editing: TimeBlock?      // 点击已有块进入编辑
    @State private var newBlock: NewBlock?      // 点击空槽：在该整点新建

    private struct NewBlock: Identifiable { let hour: Int; var id: Int { hour } }

    private var dayBlocks: [TimeBlock] {
        allBlocks.filter { $0.start.isSameDay(as: selectedDay) }
    }
    private var totalTracked: TimeInterval {
        dayBlocks.reduce(0) { $0 + $1.duration }
    }
    // 各整点对应的块（按 start 的小时归类）
    private func blocks(inHour h: Int) -> [TimeBlock] {
        dayBlocks.filter { Calendar.current.component(.hour, from: $0.start) == h }
    }
    private var nowHour: Int { Calendar.current.component(.hour, from: .now) }

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
            .navigationTitle("今日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { dayNav }
            }
            .sheet(item: $newBlock) { TimeBlockEditorView(day: selectedDay, hour: $0.hour) }
            .sheet(item: $editing) { TimeBlockEditorView(block: $0) }
        }
    }

    // 单个整点行：左侧钟点 + 右侧块（有则展示，无则空槽可点）
    private func hourRow(_ h: Int) -> some View {
        let items = blocks(inHour: h)
        let isNow = selectedDay.isSameDay(as: .now) && h == nowHour
        return HStack(alignment: .top, spacing: 10) {
            Text(String(format: "%02d:00", h))
                .font(.caption).monospacedDigit()
                .foregroundStyle(isNow ? Color.accentColor : .secondary)
                .frame(width: 44, alignment: .leading)
                .padding(.top, 6)

            if items.isEmpty {
                Button { newBlock = NewBlock(hour: h) } label: {
                    HStack {
                        Text("空闲").font(.subheadline).foregroundStyle(.tertiary)
                        Spacer()
                        Image(systemName: "plus").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 6) {
                    ForEach(items) { b in
                        Button { editing = b } label: { blockCard(b) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .listRowSeparator(.hidden)
        .padding(.vertical, 2)
    }

    private func blockCard(_ b: TimeBlock) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(b.cat.color).frame(width: 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(b.title.isEmpty ? b.cat.name : b.title).font(.subheadline)
                HStack(spacing: 6) {
                    Label(b.cat.name, systemImage: b.cat.icon).font(.caption2).foregroundStyle(b.cat.color)
                    Text("· \(b.start.hm)-\(b.end.hm) · \(formatDuration(b.duration))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(b.cat.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    // 日期切换：前一天 / 今天 / 后一天
    private var dayNav: some View {
        HStack(spacing: 12) {
            Button { selectedDay = selectedDay.addingDays(-1) } label: { Image(systemName: "chevron.left") }
            Button { selectedDay = .now } label: {
                Text(selectedDay.isSameDay(as: .now) ? "今天" : selectedDay.dayTitle)
                    .font(.subheadline).bold()
            }
            .buttonStyle(.plain)
            Button { selectedDay = selectedDay.addingDays(1) } label: { Image(systemName: "chevron.right") }
        }
    }
}
