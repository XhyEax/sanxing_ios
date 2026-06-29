//
//  ContentView.swift — 自定义底部栏：时间轴 / 随手记 / 统计 / 设置
//  不用 TabView 的 tabItem 选中机制 → 没有「重复点 Tab 回顶/弹根」的系统行为，
//  点「时间轴」回今天完全由本文件控制（todayTrigger）。
//  各页用 ZStack + opacity 常驻，切换不丢滚动/状态（与 TabView 一致）。
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var selection = 0
    @State private var todayTrigger = 0   // 点「时间轴」→ 回今天

    private struct TabDef { let id: Int; let name: String; let icon: String }
    private let tabs = [
        TabDef(id: 0, name: "时间轴", icon: "calendar.day.timeline.left"),
        TabDef(id: 1, name: "随手记", icon: "book.closed"),
        TabDef(id: 2, name: "统计", icon: "chart.bar.xaxis"),
        TabDef(id: 3, name: "设置", icon: "gearshape"),
    ]

    var body: some View {
        // 只渲染当前页：ZStack 同时存在多个 NavigationStack 会让时间轴布局错乱（左移，
        // 需滚动才恢复）。单页渲染彻底规避；代价是切换页面不保留各页滚动位置。
        Group {
            switch selection {
            case 0: TimelineView(goTodayTrigger: todayTrigger)
            case 1: DiaryView()
            case 2: StatsView()
            default: SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .center) {
                ForEach(tabs, id: \.id) { tab in
                    Button { tap(tab.id) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon).font(.system(size: 20))
                            Text(tab.name).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(selection == tab.id ? Color.accentColor : .secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        }
        .background(.bar)
    }

    private func tap(_ id: Int) {
        if id == 0 && selection == 0 { todayTrigger += 1 }   // 已在时间轴再点 → 当前时间居中
        selection = id                                       // 仅切换到时间轴：不滚动（保留原位置，无动画）
    }
}

// 兼容 Xcode 模板默认入口名
struct ContentView: View {
    var body: some View { MainTabView() }
}

#Preview {
    MainTabView()
        .modelContainer(for: [TimeBlock.self, DiaryEntry.self], inMemory: true)
}
