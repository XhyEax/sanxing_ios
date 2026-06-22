//
//  ContentView.swift — 底部 TabView：今日 / 日记 / 统计 / 设置
//  sanxing
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var selection = 0
    @State private var todayTrigger = 0   // 点「时间轴」Tab → 触发滚动
    @State private var todayPhase = 0     // 0=今天0点 1=当前第一个空闲；切入归 0，重复点切换

    var body: some View {
        TabView(selection: Binding(
            get: { selection },
            set: { newValue in
                if newValue == 0 {
                    todayPhase = (selection == 0) ? (todayPhase == 0 ? 1 : 0) : 0   // 重复点切换 / 切入归 0 点
                    todayTrigger += 1
                }
                selection = newValue
            }
        )) {
            TimelineView(goTodayTrigger: todayTrigger, goTodayPhase: todayPhase)
                .tag(0)
                .tabItem { Label("时间轴", systemImage: "calendar.day.timeline.left") }

            DiaryView()
                .tag(1)
                .tabItem { Label("日记", systemImage: "book.closed") }

            StatsView()
                .tag(2)
                .tabItem { Label("统计", systemImage: "chart.bar.xaxis") }

            SettingsView()
                .tag(3)
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
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
