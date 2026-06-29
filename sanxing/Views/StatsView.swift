// Views/StatsView.swift — 统计：可选今天/3天/7天/30天，概览 + 每日趋势 + 分类占比
import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query(sort: \TimeBlock.start) private var blocks: [TimeBlock]
    @Query private var customCats: [CustomCategory]
    @State private var rangeDays = 7   // 1=今天 / 3 / 7 / 30
    @State private var selectedKey: String?   // 趋势图选中的分类（nil → 用占比最高的）
    @State private var selectedDay: Date?      // 趋势图悬停/点选的那天

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

    // 趋势图实际展示的分类：选中的；选中项不在当前范围则退回占比最高的
    private var effectiveKey: String? {
        if let k = selectedKey, byCategory.contains(where: { $0.style.key == k }) { return k }
        return byCategory.first?.style.key
    }

    // 某分类每天的时长（升序，含无记录的 0 天），供趋势图
    private func perDay(for key: String) -> [(day: Date, seconds: TimeInterval)] {
        var dict: [Date: TimeInterval] = [:]
        for b in rangeBlocks where b.category == key {
            dict[cal.startOfDay(for: b.start), default: 0] += b.duration
        }
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
                    }
                }

                if rangeDays > 1, let key = effectiveKey {
                    let style = catStyle(for: key, custom: customCats)
                    Section("每日趋势 · \(style.name)") { dailyChart(for: key, style: style) }
                }

                if !byCategory.isEmpty {
                    Section {
                        ForEach(byCategory, id: \.style.key) { item in
                            Button { selectedKey = item.style.key } label: {
                                categoryBar(item.style, item.seconds, selected: item.style.key == effectiveKey)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("分类占比")
                    } footer: {
                        if rangeDays > 1 { Text("点击分类查看每日趋势") }
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

    private func dailyChart(for key: String, style: CatStyle) -> some View {
        let data = perDay(for: key)
        let sel = selectedDay.flatMap { s in data.first { cal.isDate($0.day, inSameDayAs: s) } }
        let avg = data.isEmpty ? 0 : data.reduce(0) { $0 + $1.seconds } / Double(data.count)
        return Chart(data, id: \.day) { item in
            BarMark(
                x: .value("日期", item.day, unit: .day),
                y: .value("时长", item.seconds / 3600)
            )
            .foregroundStyle(style.color.gradient)
            .cornerRadius(3)
            .opacity(sel == nil || cal.isDate(sel!.day, inSameDayAs: item.day) ? 1 : 0.35)

            // 平均时长：绿色虚线
            RuleMark(y: .value("平均", avg / 3600))
                .foregroundStyle(.green)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .annotation(position: .top, alignment: .trailing, spacing: 0) {
                    Text("平均 \(formatDuration(avg))").font(.caption2).foregroundStyle(.green)
                }

            // 十字交叉：跟随按下的位置（竖线=日期，横线=时长，y 轴标注具体时长）
            if let sel {
                RuleMark(x: .value("日期", sel.day, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit, y: .disabled)) {
                        Text(sel.day.monthDay).font(.caption2).foregroundStyle(.secondary)
                    }
                RuleMark(y: .value("时长", sel.seconds / 3600))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .leading, alignment: .leading, spacing: 2) {
                        Text(sel.seconds > 0 ? formatDuration(sel.seconds) : "无记录")
                            .font(.caption2).bold().foregroundStyle(style.color)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
            }
        }
        .chartXSelection(value: $selectedDay)
        .chartYAxisLabel("小时")
        .frame(height: 170)
        .padding(.vertical, 4)
    }

    private func categoryBar(_ style: CatStyle, _ seconds: TimeInterval, selected: Bool) -> some View {
        let ratio = total > 0 ? seconds / total : 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(style.name, systemImage: style.icon)
                    .font(.subheadline).fontWeight(selected ? .bold : .regular)
                    .foregroundStyle(style.color)
                if selected { Image(systemName: "chart.bar.fill").font(.caption2).foregroundStyle(style.color) }
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
