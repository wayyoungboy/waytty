import SwiftUI

struct FileBrowserView: View {
    @ObservedObject var session: TerminalSession
    @StateObject private var model: FileBrowserStore
    @State private var pathInput = ""
    @State private var selected: String?
    @State private var showingMkdir = false
    @State private var newName = ""
    @State private var deleting: BrowserFile?
    @State private var renaming: BrowserFile?

    init(session: TerminalSession) {
        self.session = session
        _model = StateObject(wrappedValue: FileBrowserStore(session: session))
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(model.isRemote ? "SFTP 文件" : "本地文件", systemImage: "folder").fontWeight(.medium)
                Spacer()
                IconButton(symbol: "arrow.clockwise", help: "刷新目录") { Task { await model.refresh() } }.disabled(model.busy)
            }.padding(.horizontal, 12).frame(height: 40)
            HStack(spacing: 4) {
                IconButton(symbol: "arrow.up", help: "上级目录") { Task { await model.parent() } }
                TextField("目录路径", text: $pathInput).textFieldStyle(.plain).font(.system(size: 10, design: .monospaced))
                    .onSubmit { Task { await model.refresh(target: pathInput) } }
                IconButton(symbol: "arrow.turn.down.left", help: "前往目录") { Task { await model.refresh(target: pathInput) } }
            }.padding(.horizontal, 7).frame(height: 31).background(Theme.canvas)
            HStack(spacing: 3) {
                IconButton(symbol: "folder.badge.plus", help: "新建目录") { newName = ""; showingMkdir = true }
                if model.isRemote { IconButton(symbol: "square.and.arrow.up", help: "上传文件") { Task { await model.upload() } } }
                IconButton(symbol: "eye", help: "显示隐藏文件", active: model.showHidden) { model.showHidden.toggle() }
                Spacer()
                if model.busy { ProgressView().controlSize(.mini) }
            }.padding(.horizontal, 10).frame(height: 36).disabled(model.busy || (model.isRemote && session.state != .running))
            Rectangle().fill(Theme.line).frame(height: 1)
            if model.isRemote && session.state != .running {
                VStack(spacing: 12) {
                    Image(systemName: "lock").font(.system(size: 24, weight: .light)).foregroundStyle(Theme.accent)
                    Text("完成 SSH 认证后\n即可浏览远程文件").multilineTextAlignment(.center).foregroundStyle(.secondary).lineSpacing(5)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.visibleFiles) { file in
                            HStack(spacing: 8) {
                                Image(systemName: file.isDirectory ? "folder.fill" : (file.isLink ? "link" : "doc"))
                                    .foregroundStyle(file.isDirectory ? Theme.accent.opacity(0.8) : Color.secondary).frame(width: 15)
                                Text(file.name).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 3)
                                if !file.isDirectory { Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)).font(.system(size: 9)).foregroundStyle(Theme.muted) }
                            }.font(.system(size: 11)).padding(.horizontal, 12).frame(height: 31)
                                .background(selected == file.name ? Theme.accent.opacity(0.1) : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { Task { await model.open(file) } }
                                .onTapGesture { selected = file.name }
                                .contextMenu {
                                    Button(file.isDirectory ? "打开目录" : (model.isRemote ? "下载…" : "打开")) { Task { await model.open(file) } }
                                    Button("复制路径") { copyToClipboard(model.path + "/" + file.name) }
                                    Button("重命名…") { newName = file.name; renaming = file }
                                    Divider(); Button(model.isRemote ? "删除…" : "移到废纸篓…", role: .destructive) { deleting = file }
                                }.help("\(file.name)\n\(file.permissions)\n\(file.modified)")
                        }
                    }
                }.disabled(model.busy)
            }
            if let error = model.error {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange).textSelection(.enabled).lineLimit(8).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.05))
            }
            HStack { Text(model.busy ? model.operation : "\(model.visibleFiles.count) 个项目"); Spacer() }.font(.system(size: 9)).foregroundStyle(Theme.muted).padding(10)
        }.background(Theme.sidebar)
            .task { pathInput = model.path; if !model.isRemote || session.state == .running { await model.refresh() } }
            .onChange(of: model.path) { _, value in pathInput = value }
            .onChange(of: session.state) { _, value in if value == .running { Task { await model.refresh() } } }
            .alert("新建目录", isPresented: $showingMkdir) {
                TextField("目录名称", text: $newName)
                Button("取消", role: .cancel) {}
                Button("创建") { Task { await model.createDirectory(newName) } }
            }
            .alert("重命名", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("新名称", text: $newName)
                Button("取消", role: .cancel) { renaming = nil }
                Button("保存") { if let file = renaming { Task { await model.rename(file, to: newName) } }; renaming = nil }
            }
            .alert(model.isRemote ? "删除远程文件？" : "移到废纸篓？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("取消", role: .cancel) { deleting = nil }
                Button("删除", role: .destructive) { if let file = deleting { Task { await model.remove(file) } }; deleting = nil }
            } message: { Text("\(deleting?.name ?? "")\n" + (model.isRemote ? "远程删除无法撤销。目录仅在为空时删除。" : "文件将移到 macOS 废纸篓。")) }
    }
}
