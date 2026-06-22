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
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.largeTitle).bold()
            ForEach(items) { it in
                if let dh = it.dayHeader {
                    Text(dh).font(.title2).bold()
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                } else if let c = it.color {
                    HStack(alignment: .top, spacing: 12) {
                        Text(it.time).font(.title3).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .leading)
                        RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 6)
                        VStack(alignment: .leading, spacing: 4) {
                            if showTitle && !it.title.isEmpty {
                                Text(it.title).font(.title3)
                            }
                            HStack(spacing: 6) {
                                Text(it.name).font(.title3).foregroundStyle(c)
                                Text("· \(it.sub)").font(.body).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        Text(it.time).font(.title3).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .leading)
                        Text("空闲 · \(it.sub)").font(.title3).foregroundStyle(.tertiary)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 480, alignment: .leading)
        .background(Color(.systemBackground))
    }
}

// 预览 + 分享面板：默认图(无标题)由父级渲染传入；勾选「显示标题」时在本面板重渲染
struct SharePreviewSheet: View {
    let image: UIImage?     // 默认（无标题）图
    let title: String
    let items: [ShareItem]
    let scheme: ColorScheme
    var jsonText: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showTitle = false
    @State private var titledImage: UIImage?   // 显示标题时重渲染
    @State private var copied = false

    private var shown: UIImage? { showTitle ? titledImage : image }

    var body: some View {
        NavigationStack {
            Group {
                if let img = shown {
                    ScrollView {
                        Image(uiImage: img)
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
                    if let img = shown {
                        ShareLink(item: Image(uiImage: img),
                                  preview: SharePreview("时间轴", image: Image(uiImage: img))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .onChange(of: showTitle) { _, on in
                if on && titledImage == nil {   // 首次切到显示标题才渲染
                    let r = ImageRenderer(content:
                        DayShareView(title: title, items: items, showTitle: true)
                            .environment(\.colorScheme, scheme))
                    r.scale = 2
                    titledImage = r.uiImage
                }
            }
        }
    }
}
