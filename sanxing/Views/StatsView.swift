// Views/StatsView.swift — 统计：可选今天/3天/7天/30天，概览 + 每日趋势 + 分类占比
import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query(sort: \TimeBlock.start) private var blocks: [TimeBlock]
    @Query private var customCats: [CustomCategory]
    @State private var rangeDays = 7   // 1=今天 / 3 / 7 / 30

    private let cal = Calendar.current
    // 含今天在内的最近 rangeDays 天
    private var rangeStart: Date { Date.now.startOfDay.addingDays(-(rangeDays - 1)) }
    private var rangeBlocks: [TimeBlock] { blocks.filter { $0.start >= rangeStart } }
    private var total: TimeInterval { rangeBlocks.reduce(0) { $0 + $1.duration } }
    private var activeDays: Int { Set(rangeBlocks.map { cal.startOfDay(for: $0.start) }).count }

    // 各分类时长，倒序（内置 + 自定义统一解析）
    private var byCategory: [(style: CatStyle, seconds: TimeInterval)] {
        var dict: [String: TimeInterval] = [:]
        for b in rangeBlocks { dict[b.category, default: 0] += b.duration }
        return dict.map { (style: catStyle(for: $0.key, custom: customCats), seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    // 每天时长（升序，含无记录的 0 天），供趋势图
    private var perDay: [(day: Date, seconds: TimeInterval)] {
        var dict: [Date: TimeInterval] = [:]
        for b in rangeBlocks { dict[cal.startOfDay(for: b.start), default: 0] += b.duration }
        return (0..<rangeDays).reversed().map { i in
            let d = Date.now.startOfDay.addingDays(-i)
            return (day: d, seconds: dict[d] ?? 0)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("范围", selection: $rangeDays) {
                        Text("今天").tag(1)
                        Text("3 天").tag(3)
                        Text("7 天").tag(7)
                        Text("30 天").tag(30)
                    }
                    .pickerStyle(.segmented)
                }

                Section("概览") {
                    statRow("已记录", formatDuration(total), bold: true)
                    statRow("时间块", "\(rangeBlocks.count)")
                    if rangeDays > 1 {
                        statRow("活跃天数", "\(activeDays) / \(rangeDays)")
                        statRow("平均每天", formatDuration(total / Double(rangeDays)))
                    }
                }

                if rangeDays > 1 && !rangeBlocks.isEmpty {
                    Section("每日时长") { dailyChart }
                }

                if !byCategory.isEmpty {
                    Section("分类占比") {
                        ForEach(byCategory, id: \.style.key) { item in
                            categoryBar(item.style, item.seconds)
                        }
                    }
                }
            }
            .navigationTitle("统计")
            .overlay {
                if rangeBlocks.isEmpty {
                    ContentUnavailableView(rangeDays == 1 ? "今日暂无数据" : "该时段暂无数据",
                                           systemImage: "chart.bar.xaxis")
                }
            }
        }
    }

    private func statRow(_ title: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).bold(bold).foregroundStyle(bold ? .primary : .secondary)
        }
    }

    private var dailyChart: some View {
        Chart(perDay, id: \.day) { item in
            BarMark(
                x: .value("日期", item.day, unit: .day),
                y: .value("时长", item.seconds / 3600)
            )
            .foregroundStyle(Color.accentColor.gradient)
            .cornerRadius(3)
        }
        .chartYAxisLabel("小时")
        .frame(height: 170)
        .padding(.vertical, 4)
    }

    private func categoryBar(_ style: CatStyle, _ seconds: TimeInterval) -> some View {
        let ratio = total > 0 ? seconds / total : 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(style.name, systemImage: style.icon).font(.subheadline).foregroundStyle(style.color)
                Spacer()
                Text("\(formatDuration(seconds)) · \(Int(ratio * 100))%")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(style.color).frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 2)
    }
}
