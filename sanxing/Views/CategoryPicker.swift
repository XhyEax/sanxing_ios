// Views/CategoryPicker.swift — 可复用分类选择网格 + 自定义标签编辑器
// 编辑器与「今日」填充菜单共用 CategoryGrid，保持图标/颜色一致。
import SwiftUI
import SwiftData

// MARK: - 分类选择网格

struct CategoryGrid: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \CustomCategory.sortOrder) private var customCats: [CustomCategory]

    var selectedKey: String? = nil          // 高亮哪个（填充菜单传 nil 不高亮）
    var onPick: (String) -> Void

    @State private var creating = false
    @State private var editingCustom: CustomCategory?

    private let columns = Array(repeating: GridItem(.flexible()), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(allCatStyles(custom: customCats)) { s in
                cell(s)
            }
            addCell
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $creating) {
            CustomCategoryEditor(nextSortOrder: (customCats.map(\.sortOrder).max() ?? -1) + 1) { key in
                onPick(key)   // 新建后直接选中/使用
            }
        }
        .sheet(item: $editingCustom) { CustomCategoryEditor(category: $0) }
    }

    private func cell(_ s: CatStyle) -> some View {
        let isSel = s.key == selectedKey
        let custom = customCats.first { $0.id == s.key }
        return Button { onPick(s.key) } label: {
            VStack(spacing: 4) {
                Image(systemName: s.icon).font(.title3)
                Text(s.name).font(.caption).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSel ? s.color.opacity(0.18) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(isSel ? s.color : .secondary)
        }
        .buttonStyle(.plain)
        .applyIf(custom != nil) { view in
            view.contextMenu {
                Button("编辑", systemImage: "pencil") { editingCustom = custom }
                Button("删除", systemImage: "trash", role: .destructive) {
                    if let c = custom { ctx.delete(c) }   // 已用到该标签的块解析时自动兜底「其他」
                }
            }
        }
    }

    private var addCell: some View {
        Button { creating = true } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus").font(.title3)
                Text("自定义").font(.caption).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 自定义标签编辑器

struct CustomCategoryEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    private let existing: CustomCategory?
    private let nextSortOrder: Int
    private let onSave: ((String) -> Void)?

    @State private var name: String
    @State private var color: Color
    @State private var icon: String

    init(nextSortOrder: Int, onSave: ((String) -> Void)? = nil) {
        existing = nil
        self.nextSortOrder = nextSortOrder
        self.onSave = onSave
        _name = State(initialValue: "")
        _color = State(initialValue: categoryPalette.first ?? .blue)
        _icon = State(initialValue: categoryIconChoices.first ?? "tag.fill")
    }

    init(category: CustomCategory, onSave: ((String) -> Void)? = nil) {
        existing = category
        nextSortOrder = category.sortOrder
        self.onSave = onSave
        _name = State(initialValue: category.name)
        _color = State(initialValue: Color(hex: category.colorHex))
        _icon = State(initialValue: category.icon)
    }

    private let swatchColumns = Array(repeating: GridItem(.flexible()), count: 8)
    private let iconColumns = Array(repeating: GridItem(.flexible()), count: 6)

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("分类名", text: $name)
                }
                Section("颜色") {
                    LazyVGrid(columns: swatchColumns, spacing: 10) {
                        ForEach(Array(categoryPalette.enumerated()), id: \.offset) { _, c in
                            Circle().fill(c)
                                .frame(height: 26)
                                .overlay(Circle().strokeBorder(.primary,
                                    lineWidth: c.toHexString() == color.toHexString() ? 2 : 0))
                                .onTapGesture { color = c }
                        }
                    }
                    .padding(.vertical, 4)
                    ColorPicker("自定义颜色", selection: $color, supportsOpacity: false)
                }
                Section("图标") {
                    LazyVGrid(columns: iconColumns, spacing: 10) {
                        ForEach(categoryIconChoices, id: \.self) { sym in
                            Image(systemName: sym).font(.title3)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .foregroundStyle(sym == icon ? color : .secondary)
                                .background(sym == icon ? color.opacity(0.18) : Color.secondary.opacity(0.08),
                                            in: RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { icon = sym }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if existing != nil {
                    Section {
                        Button("删除", role: .destructive) { delete() }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(existing == nil ? "新建标签" : "编辑标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let key: String
        if let c = existing {
            c.name = trimmed; c.colorHex = color.toHexString(); c.icon = icon
            key = c.id
        } else {
            let c = CustomCategory(name: trimmed, colorHex: color.toHexString(),
                                   icon: icon, sortOrder: nextSortOrder)
            ctx.insert(c)
            key = c.id
        }
        onSave?(key)
        dismiss()
    }

    private func delete() {
        if let c = existing { ctx.delete(c) }
        dismiss()
    }
}

// MARK: - 工具

private extension View {
    @ViewBuilder
    func applyIf<T: View>(_ condition: Bool, _ transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}
