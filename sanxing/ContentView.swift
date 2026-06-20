//
//  ContentView.swift — 底部 TabView：今日 / 日记 / 统计 / 设置
//  sanxing
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var selection = 0
    @State private var todayTrigger = 0   // 点「今日」Tab（含从别的 Tab 切回/重复点）→ 让时间轴滚回今日

    var body: some View {
        TabView(selection: Binding(
            get: { selection },
            set: { newValue in
                if newValue == 0 { todayTrigger += 1 }
                selection = newValue
            }
        )) {
            TimelineView(goTodayTrigger: todayTrigger)
                .tag(0)
                .tabItem { Label("今日", systemImage: "calendar.day.timeline.left") }

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
