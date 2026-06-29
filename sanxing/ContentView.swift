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
    @State private var timelineSelecting = false   // 时间轴多选态 → 隐藏底栏，让选择操作栏占位

    private struct TabDef { let id: Int; let name: String; let icon: String }
    private let tabs = [
        TabDef(id: 0, name: "时间轴", icon: "calendar.day.timeline.left"),
        TabDef(id: 1, name: "随手记", icon: "book.closed"),
        TabDef(id: 2, name: "统计", icon: "chart.bar.xaxis"),
        TabDef(id: 3, name: "设置", icon: "gearshape"),
    ]

    var body: some View {
        // 时间轴常驻（保留滚动/状态）；其它页按需渲染并叠在最上层。
        // 关键：可见页始终是最上层（或唯一一个），避免「被其它 NavigationStack 压在下面」导致的整体左移。
        ZStack {
            TimelineView(goTodayTrigger: todayTrigger, selecting: $timelineSelecting)
                .opacity(selection == 0 ? 1 : 0)
                .allowsHitTesting(selection == 0)
            if selection != 0 {
                Group {
                    switch selection {
                    case 1: DiaryView()
                    case 2: StatsView()
                    default: SettingsView()
                    }
                }
                .transition(.identity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !(selection == 0 && timelineSelecting) { bottomBar }   // 时间轴多选时让位给选择操作栏
        }
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
        selection = id
        if id == 0 { todayTrigger += 1 }   // 点「时间轴」（切到或重点）都回今天
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
