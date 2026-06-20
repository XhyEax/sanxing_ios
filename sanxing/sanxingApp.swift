//
//  rixingApp.swift
//  rixing
//
//  Created by xhy on 2026/6/20.
//

import SwiftUI
import SwiftData

@main
struct rixingApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TimeBlock.self,
            DiaryEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    // 0=跟随系统 1=浅色 2=深色
    @AppStorage("appColorScheme") private var colorSchemeIndex = 0
    private var preferredColorScheme: ColorScheme? {
        switch colorSchemeIndex {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(preferredColorScheme)
        }
        .modelContainer(sharedModelContainer)
    }
}
