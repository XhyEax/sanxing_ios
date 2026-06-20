// Models/CustomCategory.swift — 用户自定义分类（标题 + 颜色 + 图标）
import Foundation
import SwiftData

@Model
final class CustomCategory {
    // 默认值是 CloudKit 同步的硬性要求（每个属性须可选或有默认值）；实际值由 init 覆盖。
    // id 是存进 TimeBlock.category 的 key——用 UUID 字符串，不会与内置 BlockCategory.rawValue 撞。
    var id: String = UUID().uuidString
    var name: String = ""
    var colorHex: String = "#8E8E93"
    var icon: String = "tag.fill"
    var sortOrder: Int = 0

    init(name: String, colorHex: String, icon: String, sortOrder: Int = 0) {
        self.id = UUID().uuidString
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
        self.sortOrder = sortOrder
    }
}
