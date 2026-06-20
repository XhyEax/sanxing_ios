// Views/DiaryEditorView.swift — 新建/编辑日记条目
import SwiftUI
import SwiftData

struct DiaryEditorView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    private let existing: DiaryEntry?
    @State private var text: String
    @State private var mood: Int
    @State private var createdAt: Date

    init() {
        existing = nil
        _text = State(initialValue: "")
        _mood = State(initialValue: 0)
        _createdAt = State(initialValue: .now)
    }
    init(entry: DiaryEntry) {
        existing = entry
        _text = State(initialValue: entry.text)
        _mood = State(initialValue: entry.mood)
        _createdAt = State(initialValue: entry.createdAt)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("心情") { moodPicker }
                Section("正文") {
                    TextField("写点什么…", text: $text, axis: .vertical)
                        .lineLimit(6...20)
                }
                Section("时间") {
                    DatePicker("记录时间", selection: $createdAt)
                }
                if existing != nil {
                    Section {
                        Button("删除", role: .destructive) { delete() }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(existing == nil ? "写日记" : "编辑日记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var moodPicker: some View {
        HStack {
            ForEach(1...5, id: \.self) { m in
                Button { mood = (mood == m) ? 0 : m } label: {
                    Text(Mood.emoji(m))
                        .font(.title2)
                        .padding(6)
                        .background(mood == m ? Color.accentColor.opacity(0.18) : .clear,
                                    in: Circle())
                }
                .buttonStyle(.plain)
                if m < 5 { Spacer() }
            }
        }
        .padding(.vertical, 2)
    }

    private func save() {
        if let e = existing {
            e.text = text; e.mood = mood; e.createdAt = createdAt
        } else {
            ctx.insert(DiaryEntry(createdAt: createdAt, text: text, mood: mood))
        }
        dismiss()
    }

    private func delete() {
        if let e = existing { ctx.delete(e) }
        dismiss()
    }
}
