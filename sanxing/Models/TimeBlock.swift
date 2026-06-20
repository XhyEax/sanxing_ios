// Models/TimeBlock.swift — 时间块（计划/记录通用：一段有起止时间的事项）
import Foundation
import SwiftData
import SwiftUI

@Model
final class TimeBlock {
    // 默认值是 CloudKit 同步的硬性要求（每个属性须可选或有默认值）；实际值由 init 覆盖
    var start: Date = Date.now
    var end: Date = Date.now
    var title: String = ""
    var category: String = BlockCategory.other.rawValue   // 分类 key，见 BlockCategory.rawValue
    var note: String = ""

    init(start: Date, end: Date, title: String,
         category: String = BlockCategory.other.rawValue, note: String = "") {
        self.start = start
        self.end = end
        self.title = title
        self.category = category
        self.note = note
    }

    /// 时长（秒，至少 0）
    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    var cat: BlockCategory { BlockCategory(rawValue: category) ?? .other }
}

// 时间块分类：颜色 + 图标 + 名称（先内置一组，后续可做成可配置）
enum BlockCategory: String, CaseIterable, Identifiable {
    case work, study, rest, exercise, life, fun, other
    var id: String { rawValue }

    var name: String {
        switch self {
        case .work: return "工作"
        case .study: return "学习"
        case .rest: return "睡眠"
        case .exercise: return "运动"
        case .life: return "生活"
        case .fun: return "娱乐"
        case .other: return "其他"
        }
    }
    var color: Color {
        switch self {
        case .work: return .blue
        case .study: return .purple
        case .rest: return .teal
        case .exercise: return .orange
        case .life: return .pink
        case .fun: return .green
        case .other: return .brown   // 原灰色对比度低、看不清，改棕色
        }
    }
    var icon: String {
        switch self {
        case .work: return "briefcase.fill"
        case .study: return "book.fill"
        case .rest: return "bed.double.fill"
        case .exercise: return "figure.run"
        case .life: return "house.fill"
        case .fun: return "gamecontroller.fill"
        case .other: return "circle.fill"
        }
    }
}
