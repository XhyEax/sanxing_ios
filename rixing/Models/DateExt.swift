// Models/DateExt.swift — 日期/时间工具
import Foundation

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    var endOfDay: Date { startOfDay.addingDays(1) }

    func addingDays(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: self) ?? self
    }
    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    /// "15:30"
    var hm: String { formatted(date: .omitted, time: .shortened) }

    /// "6月20日 周五"
    var dayTitle: String {
        formatted(.dateTime.month(.wide).day().weekday(.wide).locale(Locale(identifier: "zh_CN")))
    }
}

/// 时长格式化："1小时30分" / "45分钟"
func formatDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds) / 60
    let h = total / 60, m = total % 60
    if h > 0 && m > 0 { return "\(h)小时\(m)分" }
    if h > 0 { return "\(h)小时" }
    return "\(m)分钟"
}
