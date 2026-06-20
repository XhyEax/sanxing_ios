// Views/SettingsView.swift — 设置：主题 + 数据导入导出 + 关于
import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @AppStorage("appColorScheme") private var colorSchemeIndex = 0

    @Environment(\.modelContext) private var ctx
    @Query private var blocks: [TimeBlock]
    @Query private var diaries: [DiaryEntry]
    @Query private var cats: [CustomCategory]

    @State private var exportDoc: JSONDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingPlan: ImportPlan?
    @State private var addedBeforeConflict = 0
    @State private var showConflict = false
    @State private var alertMsg: String?

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

                Section("数据") {
                    Button { exportToFile() } label: {
                        Label("导出到文件", systemImage: "square.and.arrow.up")
                    }
                    Button { copyToClipboard() } label: {
                        Label("复制到剪贴板", systemImage: "doc.on.doc")
                    }
                    Button { showImporter = true } label: {
                        Label("从文件导入", systemImage: "square.and.arrow.down")
                    }
                    Button { importFromClipboard() } label: {
                        Label("从剪贴板导入", systemImage: "doc.on.clipboard")
                    }
                } footer: {
                    Text("导出为 JSON（时间块 / 日记 / 自定义分类）。导入时若条目已存在，可选择覆盖或跳过。")
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
            .fileExporter(isPresented: $showExporter, document: exportDoc,
                          contentType: .json, defaultFilename: DataTransfer.fileName()) { result in
                if case .failure = result { alertMsg = "导出失败" }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                handleFileImport(result)
            }
            .alert("有 \(pendingPlan?.conflictCount ?? 0) 条已存在",
                   isPresented: $showConflict, presenting: pendingPlan) { plan in
                Button("覆盖") { applyConflicts(plan, overwrite: true) }
                Button("跳过") { applyConflicts(plan, overwrite: false) }
                Button("取消", role: .cancel) { pendingPlan = nil }
            } message: { _ in
                Text("已新增 \(addedBeforeConflict) 条；重复的要覆盖还是跳过？")
            }
            .alert(alertMsg ?? "", isPresented: Binding(
                get: { alertMsg != nil }, set: { if !$0 { alertMsg = nil } }
            )) { Button("好的", role: .cancel) {} }
        }
    }

    // MARK: - 导出

    private var backup: BackupData {
        BackupData(version: 1,
                   blocks: blocks.map(\.dto),
                   diaries: diaries.map(\.dto),
                   categories: cats.map(\.dto))
    }

    private func exportToFile() {
        guard let data = DataTransfer.encode(backup) else { alertMsg = "导出失败"; return }
        exportDoc = JSONDocument(data: data)
        showExporter = true
    }

    private func copyToClipboard() {
        guard let data = DataTransfer.encode(backup), let s = String(data: data, encoding: .utf8) else {
            alertMsg = "导出失败"; return
        }
        UIPasteboard.general.string = s
        alertMsg = "已复制到剪贴板"
    }

    // MARK: - 导入

    private func importFromClipboard() {
        guard let s = UIPasteboard.general.string, let data = s.data(using: .utf8) else {
            alertMsg = "剪贴板无内容"; return
        }
        runImport(data)
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { alertMsg = "读取文件失败"; return }
            runImport(data)
        case .failure:
            alertMsg = "导入已取消"
        }
    }

    private func runImport(_ data: Data) {
        guard let b = DataTransfer.decode(data) else { alertMsg = "数据格式不正确"; return }
        let plan = DataTransfer.plan(b,
                                     existingBlockStarts: Set(blocks.map(\.start)),
                                     existingDiaryDates: Set(diaries.map(\.createdAt)),
                                     existingCatIDs: Set(cats.map(\.id)))
        // 先把不冲突的直接新增
        for d in plan.newCats { ctx.insert(CustomCategory(dto: d)) }
        for d in plan.newBlocks { ctx.insert(TimeBlock(dto: d)) }
        for d in plan.newDiaries { ctx.insert(DiaryEntry(dto: d)) }
        addedBeforeConflict = plan.addedCount

        if plan.conflictCount > 0 {
            pendingPlan = plan
            showConflict = true
        } else {
            alertMsg = "导入完成：新增 \(plan.addedCount) 条"
        }
    }

    private func applyConflicts(_ plan: ImportPlan, overwrite: Bool) {
        if overwrite {
            for d in plan.conflictCats {
                cats.first { $0.id == d.id }.map { ctx.delete($0) }
                ctx.insert(CustomCategory(dto: d))
            }
            for d in plan.conflictBlocks {
                blocks.first { $0.start == d.start }.map { ctx.delete($0) }
                ctx.insert(TimeBlock(dto: d))
            }
            for d in plan.conflictDiaries {
                diaries.first { $0.createdAt == d.createdAt }.map { ctx.delete($0) }
                ctx.insert(DiaryEntry(dto: d))
            }
            alertMsg = "导入完成：新增 \(addedBeforeConflict) 条，覆盖 \(plan.conflictCount) 条"
        } else {
            alertMsg = "导入完成：新增 \(addedBeforeConflict) 条，跳过 \(plan.conflictCount) 条"
        }
        pendingPlan = nil
    }
}
