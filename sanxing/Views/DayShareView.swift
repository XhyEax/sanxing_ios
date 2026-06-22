// Views/DayShareView.swift — 分享用的日程图（ImageRenderer 渲染）+ 预览分享面板
import SwiftUI
import UIKit

// 一行：天分隔标题（dayHeader 非空）/ 块（color 非空，name=分类名、title=块自己的标题）/ 空闲（color==nil）
struct ShareItem: Identifiable {
    let id = UUID()
    var dayHeader: String? = nil
    var time: String = ""
    var name: String = ""       // 分类名 / 「空闲」
    var title: String = ""      // 块自己的标题（可空，受「显示标题」开关控制）
    var sub: String = ""        // 时间段 · 时长
    var color: Color? = nil
}

// 渲染成图的日程视图（固定宽度，便于导出）
struct DayShareView: View {
    let title: String
    let items: [ShareItem]
    var showTitle: Bool = false   // 是否显示块标题

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ForEach(items) { it in
                if let dh = it.dayHeader {
                    Text(dh).font(.subheadline).bold()
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                } else if let c = it.color {
                    HStack(alignment: .top, spacing: 10) {
                        Text(it.time).font(.caption).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)
                        RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 4)
                        VStack(alignment: .leading, spacing: 2) {
                            if showTitle && !it.title.isEmpty {
                                Text(it.title).font(.subheadline)
                            }
                            HStack(spacing: 6) {
                                Text(it.name).font(.caption2).foregroundStyle(c)
                                Text("· \(it.sub)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        Text(it.time).font(.caption).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)
                        Text("空闲 · \(it.sub)").font(.caption).foregroundStyle(.tertiary)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 360, alignment: .leading)
        .background(Color(.systemBackground))
    }
}

// 预览 + 分享面板：左上勾选「显示标题」（默认不显示），即时重渲染
struct SharePreviewSheet: View {
    let title: String
    let items: [ShareItem]
    let scheme: ColorScheme
    var jsonText: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showTitle = false
    @State private var image: UIImage?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    ScrollView {
                        Image(uiImage: image)
                            .resizable().scaledToFit()
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                } else {
                    ProgressView("生成中…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("分享预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                    Button { showTitle.toggle() } label: {   // 勾选框：是否显示标题
                        Label("标题", systemImage: showTitle ? "checkmark.square.fill" : "square")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        if let j = jsonText { UIPasteboard.general.string = j; copied = true }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(jsonText == nil)
                    if let image {
                        ShareLink(item: Image(uiImage: image),
                                  preview: SharePreview("时间轴", image: Image(uiImage: image))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .onAppear { render() }
            .onChange(of: showTitle) { _, _ in render() }
        }
    }

    private func render() {
        let r = ImageRenderer(content:
            DayShareView(title: title, items: items, showTitle: showTitle)
                .environment(\.colorScheme, scheme))
        r.scale = 2
        image = r.uiImage
    }
}
