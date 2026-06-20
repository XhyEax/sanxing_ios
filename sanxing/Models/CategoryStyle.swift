// Models/CategoryStyle.swift — 分类样式统一解析（内置枚举 + 自定义分类）+ 颜色/图标可配置素材
import SwiftUI
import UIKit

// 解析后的分类样式：name/color/icon 来自内置 BlockCategory 或 CustomCategory。
// key 即 TimeBlock.category 里存的字符串（内置 rawValue 或自定义 id）。
struct CatStyle: Equatable, Identifiable {
    let key: String
    let name: String
    let icon: String
    let color: Color
    var id: String { key }
}

// 把 TimeBlock.category 的 key 解析成样式：内置 → 枚举；否则查自定义；都找不到兜底「其他」。
func catStyle(for key: String, custom: [CustomCategory]) -> CatStyle {
    if let b = BlockCategory(rawValue: key) {
        return CatStyle(key: key, name: b.name, icon: b.icon, color: b.color)
    }
    if let c = custom.first(where: { $0.id == key }) {
        return CatStyle(key: c.id, name: c.name, icon: c.icon, color: Color(hex: c.colorHex))
    }
    return CatStyle(key: key, name: "其他", icon: "circle.fill", color: .brown)
}

// 选择器里要展示的全部分类：内置（allCases，other 在末尾）+ 自定义（按 sortOrder，排在 other 右边）。
func allCatStyles(custom: [CustomCategory]) -> [CatStyle] {
    let builtin = BlockCategory.allCases.map {
        CatStyle(key: $0.rawValue, name: $0.name, icon: $0.icon, color: $0.color)
    }
    let customs = custom.sorted { $0.sortOrder < $1.sortOrder }.map {
        CatStyle(key: $0.id, name: $0.name, icon: $0.icon, color: Color(hex: $0.colorHex))
    }
    return builtin + customs
}

// MARK: - 自定义分类可选素材

// 颜色板：比内置一组更大，自定义标签从这里挑（也可用 ColorPicker 调任意色）。
let categoryPalette: [Color] = [
    .red, .orange, .yellow, .green, .mint, .teal,
    .cyan, .blue, .indigo, .purple, .pink, .brown,
    Color(red: 0.55, green: 0.27, blue: 0.07),   // 深棕
    Color(red: 0.40, green: 0.40, blue: 0.45),   // 石墨灰
    Color(red: 0.20, green: 0.55, blue: 0.50),   // 墨绿
    Color(red: 0.85, green: 0.45, blue: 0.60),   // 玫瑰
]

// 图标库：自定义标签可选的 SF Symbol。
let categoryIconChoices: [String] = [
    "tag.fill", "star.fill", "heart.fill", "flag.fill", "bell.fill", "bookmark.fill",
    "cart.fill", "fork.knife", "cup.and.saucer.fill", "leaf.fill", "pawprint.fill", "music.note",
    "paintbrush.fill", "camera.fill", "airplane", "car.fill", "bicycle", "tram.fill",
    "moon.fill", "sun.max.fill", "cloud.fill", "drop.fill", "flame.fill", "bolt.fill",
    "person.2.fill", "gift.fill", "creditcard.fill", "stethoscope", "pills.fill", "dumbbell.fill",
]

// MARK: - Color <-> Hex

extension Color {
    // 解析 "#RRGGBB" / "RRGGBB"；非法时回退中性灰。
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else {
            self = Color(red: 0.56, green: 0.56, blue: 0.58); return
        }
        self = Color(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255)
    }

    // 转 "#RRGGBB" 存库（ColorPicker 选完后调用）。
    func toHexString() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let clamp = { (x: CGFloat) -> Int in min(255, max(0, Int((x * 255).rounded()))) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}
