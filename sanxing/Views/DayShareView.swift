// Views/DayShareView.swift — 分享用的日程图（ImageRenderer 渲染）+ 预览分享面板
import SwiftUI
import UIKit

// 一行：块（带分类色）或空闲（color == nil）
struct ShareItem: Identifiable {
    let id = UUID()
    let time: String
    let title: String
    let sub: String
    let color: Color?
}

// 渲染成图的日程视图（固定宽度，便于导出）
struct DayShareView: View {
    let title: String
    let items: [ShareItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { it in
                    HStack(alignment: .top, spacing: 10) {
                        Text(it.time).font(.caption).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)
                        if let c = it.color {
                            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(it.title).font(.subheadline)
                                Text(it.sub).font(.caption2).foregroundStyle(.secondary)
                            }
                        } else {
                            Text("空闲 · \(it.sub)").font(.caption).foregroundStyle(.tertiary)
                                .padding(.top, 1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            Text("三省小记").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: 360, alignment: .leading)
        .background(Color(.systemBackground))
    }
}

// 预览 + 分享面板：先看到生成的图，再点「分享」走系统分享
struct SharePreviewSheet: View {
    let image: UIImage?     // nil = 渲染中
    @Environment(\.dismiss) private var dismiss

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
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                if let image {
                    ToolbarItem(placement: .confirmationAction) {
                        ShareLink(item: Image(uiImage: image),
                                  preview: SharePreview("时间轴", image: Image(uiImage: image))) {
                            Text("分享")
                        }
                    }
                }
            }
        }
    }
}
