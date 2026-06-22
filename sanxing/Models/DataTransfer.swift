// Models/DataTransfer.swift — 数据导入导出（JSON 备份，参考 xiaoyaoju 的 DTO + ISO8601 + 覆盖/跳过）
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - 传输用 DTO（与 @Model 解耦，ISO8601 编码日期）

struct TimeBlockDTO: Codable {
    var start: Date
    var end: Date
    var title: String
    var category: String
    var note: String
}

struct DiaryEntryDTO: Codable {
    var createdAt: Date
    var text: String
    var mood: Int
}

struct CustomCategoryDTO: Codable {
    var id: String
    var name: String
    var colorHex: String
    var icon: String
    var sortOrder: Int
}

// 整包备份（带版本号，便于以后迁移）
struct BackupData: Codable {
    var version: Int = 1
    var blocks: [TimeBlockDTO] = []
    var diaries: [DiaryEntryDTO] = []
    var categories: [CustomCategoryDTO] = []
}

// MARK: - @Model ↔ DTO

extension TimeBlock {
    var dto: TimeBlockDTO {
        TimeBlockDTO(start: start, end: end, title: title, category: category, note: note)
    }
    convenience init(dto: TimeBlockDTO) {
        self.init(start: dto.start, end: dto.end, title: dto.title, category: dto.category, note: dto.note)
    }
}

extension DiaryEntry {
    var dto: DiaryEntryDTO { DiaryEntryDTO(createdAt: createdAt, text: text, mood: mood) }
    convenience init(dto: DiaryEntryDTO) {
        self.init(createdAt: dto.createdAt, text: dto.text, mood: dto.mood)
    }
}

extension CustomCategory {
    var dto: CustomCategoryDTO {
        CustomCategoryDTO(id: id, name: name, colorHex: colorHex, icon: icon, sortOrder: sortOrder)
    }
    convenience init(dto: CustomCategoryDTO) {
        self.init(name: dto.name, colorHex: dto.colorHex, icon: dto.icon, sortOrder: dto.sortOrder)
        self.id = dto.id   // 保留原 id，使时间块的 category 引用仍然成立
    }
}

// MARK: - 导入分流（按 key 去重 → 可直接新增 / key 重复待决定覆盖或跳过）

struct ImportPlan {
    var newBlocks: [TimeBlockDTO] = []
    var conflictBlocks: [TimeBlockDTO] = []
    var newDiaries: [DiaryEntryDTO] = []
    var conflictDiaries: [DiaryEntryDTO] = []
    var newCats: [CustomCategoryDTO] = []
    var conflictCats: [CustomCategoryDTO] = []

    var addedCount: Int { newBlocks.count + newDiaries.count + newCats.count }
    var conflictCount: Int { conflictBlocks.count + conflictDiaries.count + conflictCats.count }
}

// MARK: - 编解码 + 分流

enum DataTransfer {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return e
    }
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func encode(_ b: BackupData) -> Data? { try? encoder().encode(b) }

    // 本地时间编码（截图预览「复制」用，便于直接阅读；正式导出仍用 ISO8601）
    static func localEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.locale = Locale(identifier: "zh_CN")   // 当前时区
        e.dateEncodingStrategy = .formatted(df)
        return e
    }
    static func encodeLocal(_ b: BackupData) -> Data? { try? localEncoder().encode(b) }
    static func decode(_ data: Data) -> BackupData? { try? decoder().decode(BackupData.self, from: data) }

    // 时间块按 start、日记按 createdAt、自定义分类按 id 判重
    static func plan(_ b: BackupData,
                     existingBlockStarts: Set<Date>,
                     existingDiaryDates: Set<Date>,
                     existingCatIDs: Set<String>) -> ImportPlan {
        var p = ImportPlan()
        for d in b.blocks {
            if existingBlockStarts.contains(d.start) { p.conflictBlocks.append(d) } else { p.newBlocks.append(d) }
        }
        for d in b.diaries {
            if existingDiaryDates.contains(d.createdAt) { p.conflictDiaries.append(d) } else { p.newDiaries.append(d) }
        }
        for d in b.categories {
            if existingCatIDs.contains(d.id) { p.conflictCats.append(d) } else { p.newCats.append(d) }
        }
        return p
    }

    static func fileName(date: Date = .now) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmm"
        f.locale = Locale(identifier: "zh_CN")
        return "三省小记备份_" + f.string(from: date)
    }
}

// MARK: - 导出用 FileDocument（配合 .fileExporter）

struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
