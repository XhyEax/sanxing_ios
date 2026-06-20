// Models/TimeBlock.swift — 时间块（计划/记录通用：一段有起止时间的事项）
import Foundation
import SwiftData
import SwiftUI

@Model
final class TimeBlock {
    var start: Date
    var end: Date
    var title: String
    var category: String   // 分类 key，见 BlockCategory.rawValue
    var note: String

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
    case work, study, rest, exercise, life, other
    var id: String { rawValue }

    var name: String {
        switch self {
        case .work: return "工作"
        case .study: return "学习"
        case .rest: return "休息"
        case .exercise: return "运动"
        case .life: return "生活"
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
        case .other: return .gray
        }
    }
    var icon: String {
        switch self {
        case .work: return "briefcase.fill"
        case .study: return "book.fill"
        case .rest: return "cup.and.saucer.fill"
        case .exercise: return "figure.run"
        case .life: return "house.fill"
        case .other: return "circle.fill"
        }
    }
}
