import SwiftUI
import TerminalCore

struct SnippetsView: View {
    @EnvironmentObject var store: AppStore
    @State private var editing: Snippet?
    @State private var search = ""
    @State private var deleting: Snippet?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("命令库").font(.system(size: 23, weight: .medium))
                    Text("把常用命令，放在触手可及的地方。").foregroundStyle(.secondary)
                }
                Spacer()
                TextField("搜索命令…", text: $search).textFieldStyle(.roundedBorder).frame(width: 220)
                Button { editing = Snippet(title: "", command: "") } label: { Label("新建命令", systemImage: "plus") }.buttonStyle(ActionButtonStyle(primary: true))
            }.padding(28)
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    ForEach(store.document.snippets.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.command.localizedCaseInsensitiveContains(search) }) { snippet in
                        VStack(alignment: .leading, spacing: 15) {
                            HStack {
                                Image(systemName: "bolt.fill").foregroundStyle(Theme.accent)
                                Text(snippet.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Spacer()
                                Menu {
                                    Button("编辑") { editing = snippet }
                                    Button("删除", role: .destructive) { deleting = snippet }
                                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 20)
                            }
                            Text(snippet.command).font(.system(size: 11, design: .monospaced)).lineLimit(3).textSelection(.enabled)
                                .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                                .padding(12).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 5))
                            HStack {
                                Button { copyToClipboard(snippet.command) } label: { Label("复制", systemImage: "doc.on.doc") }.buttonStyle(ActionButtonStyle())
                                Spacer()
                                Button("插入当前终端") {
                                    guard let session = store.activeSession else { return }
                                    store.page = .terminal
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { session.insert(snippet.command) }
                                }.buttonStyle(ActionButtonStyle(primary: true)).disabled(store.activeSession == nil || store.activeSession?.state == .ended)
                            }
                        }.padding(18).background(Theme.panel, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
                    }
                }.padding(28)
            }
        }
        .sheet(item: $editing) { snippet in
            SnippetEditor(snippet: snippet) { saved in
                if let i = store.document.snippets.firstIndex(where: { $0.id == saved.id }) { store.document.snippets[i] = saved }
                else { store.document.snippets.append(saved) }; store.save()
            }
        }
        .alert("删除命令？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除", role: .destructive) { store.document.snippets.removeAll { $0.id == deleting?.id }; store.save(); deleting = nil }
        }
    }
}

private struct SnippetEditor: View {
    @Environment(\.dismiss) var dismiss
    @State var snippet: Snippet
    var save: (Snippet) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑快捷命令").font(.system(size: 17, weight: .medium))
            TextField("命令名称", text: $snippet.title).textFieldStyle(.roundedBorder)
            TextEditor(text: $snippet.command).font(.system(size: 13, design: .monospaced)).scrollContentBackground(.hidden)
                .padding(10).frame(height: 170).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 6))
            Text("命令只会插入终端，按回车后执行。").font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save(snippet); dismiss() }.buttonStyle(ActionButtonStyle(primary: true))
                    .disabled(snippet.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || snippet.command.isEmpty)
            }
        }.padding(24).frame(width: 540).background(Theme.elevated).preferredColorScheme(.dark)
    }
}

struct NotesView: View {
    @EnvironmentObject var store: AppStore
    @State private var selected: UUID?
    @State private var deleting: Note?
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack { Text("笔记").font(.system(size: 13, weight: .medium)); Spacer(); IconButton(symbol: "square.and.pencil", help: "新建笔记") { let note = Note(); store.document.notes.insert(note, at: 0); selected = note.id; store.save() } }.padding(14)
                Divider()
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.document.notes) { note in
                            Button { selected = note.id } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(note.title.isEmpty ? "未命名笔记" : note.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text(note.body.isEmpty ? "空白笔记" : note.body).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(13)
                                    .background(selected == note.id ? Theme.accent.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain).contextMenu { Button("删除笔记", role: .destructive) { deleting = note } }
                        }
                    }.padding(8)
                }
            }.frame(width: 250).background(Theme.sidebar)
            Rectangle().fill(Theme.line).frame(width: 1)
            if let id = selected, let index = store.document.notes.firstIndex(where: { $0.id == id }) {
                NoteEditor(note: $store.document.notes[index], save: store.save).id(id)
            } else {
                VStack(spacing: 15) {
                    Image(systemName: "book.closed").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(Theme.accent)
                    Text("记录命令之外的灵感").font(.system(size: 21, weight: .medium))
                    Text("运维记录、部署步骤、备忘清单，全部保存在本机。").foregroundStyle(.secondary)
                    Button("新建笔记") { let note = Note(); store.document.notes.insert(note, at: 0); selected = note.id; store.save() }.buttonStyle(ActionButtonStyle(primary: true))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.onAppear { if selected == nil { selected = store.document.notes.first?.id } }
            .alert("删除笔记？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("取消", role: .cancel) { deleting = nil }
                Button("删除", role: .destructive) { store.document.notes.removeAll { $0.id == deleting?.id }; store.save(); selected = store.document.notes.first?.id; deleting = nil }
            }
    }
}

private struct NoteEditor: View {
    @Binding var note: Note
    var save: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Label("本地笔记 · 自动保存", systemImage: "checkmark.circle").font(.system(size: 10)).foregroundStyle(Theme.muted); Spacer() }
            TextField("笔记标题", text: $note.title).font(.system(size: 26, weight: .medium)).textFieldStyle(.plain)
            Rectangle().fill(Theme.line).frame(height: 1)
            TextEditor(text: $note.body).font(.system(size: 14)).scrollContentBackground(.hidden).lineSpacing(6)
        }.padding(32).onChange(of: note) { _, _ in save() }
    }
}
