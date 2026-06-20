//
//  ContentView.swift — 底部 TabView：今日 / 日记 / 统计 / 设置
//  sanxing
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    var body: some View {
        TabView {
            TimelineView()
                .tabItem { Label("今日", systemImage: "calendar.day.timeline.left") }

            DiaryView()
                .tabItem { Label("日记", systemImage: "book.closed") }

            StatsView()
                .tabItem { Label("统计", systemImage: "chart.bar.xaxis") }

            SettingsView()
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
