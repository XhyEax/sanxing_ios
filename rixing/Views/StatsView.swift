// Views/StatsView.swift — 统计：今日各分类时长占比（骨架版）
import SwiftUI
import SwiftData

struct StatsView: View {
    @Query(sort: \TimeBlock.start) private var blocks: [TimeBlock]
    @State private var day: Date = .now

    private var dayBlocks: [TimeBlock] { blocks.filter { $0.start.isSameDay(as: day) } }
    private var total: TimeInterval { dayBlocks.reduce(0) { $0 + $1.duration } }

    // 各分类时长，倒序
    private var byCategory: [(cat: BlockCategory, seconds: TimeInterval)] {
        var dict: [BlockCategory: TimeInterval] = [:]
        for b in dayBlocks { dict[b.cat, default: 0] += b.duration }
        return dict.map { (cat: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("今日已记录")
                        Spacer()
                        Text(formatDuration(total)).bold()
                    }
                    HStack {
                        Text("时间块数量")
                        Spacer()
                        Text("\(dayBlocks.count)").foregroundStyle(.secondary)
                    }
                }
                if !byCategory.isEmpty {
                    Section("分类占比") {
                        ForEach(byCategory, id: \.cat) { item in
                            categoryBar(item.cat, item.seconds)
                        }
                    }
                }
            }
            .navigationTitle("统计")
            .overlay {
                if dayBlocks.isEmpty {
                    ContentUnavailableView("今日暂无数据", systemImage: "chart.bar.xaxis")
                }
            }
        }
    }

    private func categoryBar(_ cat: BlockCategory, _ seconds: TimeInterval) -> some View {
        let ratio = total > 0 ? seconds / total : 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(cat.name, systemImage: cat.icon).font(.subheadline).foregroundStyle(cat.color)
                Spacer()
                Text("\(formatDuration(seconds)) · \(Int(ratio * 100))%")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(cat.color).frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 2)
    }
}
