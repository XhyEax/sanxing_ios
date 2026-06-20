// Views/SettingsView.swift — 设置：主题 + 关于
import SwiftUI

struct SettingsView: View {
    @AppStorage("appColorScheme") private var colorSchemeIndex = 0

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "版本 \(v)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("外观") {
                    Picker("主题", selection: $colorSchemeIndex) {
                        Text("跟随系统").tag(0)
                        Text("浅色").tag(1)
                        Text("深色").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    HStack {
                        Text("关于")
                        Spacer()
                        Text("三省小记").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(appVersion).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("记录每一段时间，写下每一天。")
                }
            }
            .navigationTitle("设置")
        }
    }
}
