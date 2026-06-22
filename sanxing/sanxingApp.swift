//
//  sanxingApp.swift
//  sanxing
//
//  Created by xhy on 2026/6/20.
//

import SwiftUI
import SwiftData

@main
struct sanxingApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TimeBlock.self,
            DiaryEntry.self,
            CustomCategory.self,
        ])
        // 云端镜像：本地存一份 SQLite，同时同步到 iCloud 私有库。
        // 底层 NSPersistentCloudKitContainer 始终保留本地副本——切 iCloud 账号本地数据不丢。
        // 给主上下文挂 UndoManager，支持时间块/日记的撤销与恢复
        func withUndo(_ c: ModelContainer) -> ModelContainer {
            c.mainContext.undoManager = UndoManager()
            return c
        }
        let cloudConfig = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.xhy.sanxing"))
        if let container = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
            return withUndo(container)
        }
        // 兜底：iCloud 不可用/未登录/容器未配好时，退回纯本地存储，保证「本地一份」永远在、App 不崩。
        let localConfig = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        do {
            return withUndo(try ModelContainer(for: schema, configurations: [localConfig]))
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
