import SwiftUI
import TerminalCore

struct TerminalWorkspace: View {
    @EnvironmentObject var store: AppStore
    @State private var closingSession: TerminalSession?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(store.sessions) { session in
                            SessionTab(session: session, selected: store.activeSessionID == session.id,
                                       select: { if store.splitSessionID == session.id { store.splitSessionID = store.activeSessionID }; store.activeSessionID = session.id },
                                       close: { if session.state == .ended { store.closeSession(session) } else { closingSession = session } })
                        }
                    }
                }
                IconButton(symbol: "plus", help: "新建本地终端") { store.newLocalTerminal() }
                Rectangle().fill(Theme.line).frame(width: 1, height: 18).padding(.horizontal, 8)
                IconButton(symbol: "rectangle.split.2x1", help: "分屏终端", active: store.splitSessionID != nil) { store.splitTerminal() }.disabled(store.activeSession == nil)
                IconButton(symbol: "folder", help: "文件管理", active: store.showFiles) { store.showFiles.toggle() }
                IconButton(symbol: "sidebar.right", help: "会话信息", active: store.showInspector) { store.showInspector.toggle() }
            }.padding(.trailing, 10).frame(height: 39).background(Theme.panel)
            Rectangle().fill(Theme.line).frame(height: 1)
            if let session = store.activeSession {
                HStack(spacing: 0) {
                    if store.showFiles {
                        FileBrowserView(session: session).id(session.id).frame(width: 300)
                        Rectangle().fill(Theme.line).frame(width: 1)
                    }
                    HSplitView {
                        TerminalPane(session: session).id(session.id).frame(minWidth: 260)
                        if let split = store.sessions.first(where: { $0.id == store.splitSessionID }), split.id != session.id {
                            TerminalPane(session: split).id(split.id).frame(minWidth: 260)
                        }
                    }
                    if store.showInspector && store.splitSessionID == nil {
                        Rectangle().fill(Theme.line).frame(width: 1)
                        SessionInspector(session: session).id(session.id).frame(width: 226)
                    }
                }
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "terminal").font(.system(size: 46, weight: .ultraLight)).foregroundStyle(Theme.accent)
                    Text("准备好，开始下一次探索").font(.system(size: 20, weight: .medium))
                    Text("打开本地终端，或从连接仓库选择一台服务器。").foregroundStyle(.secondary)
                    HStack {
                        Button("本地终端  ⌘T") { store.newLocalTerminal() }.buttonStyle(ActionButtonStyle(primary: true))
                        Button("连接仓库") { store.page = .connections }.buttonStyle(ActionButtonStyle())
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.alert("关闭此会话？", isPresented: Binding(get: { closingSession != nil }, set: { if !$0 { closingSession = nil } })) {
            Button("取消", role: .cancel) { closingSession = nil }
            Button("关闭会话", role: .destructive) { if let session = closingSession { store.closeSession(session) }; closingSession = nil }
        } message: { Text("“\(closingSession?.kind.title ?? "")”中的进程和连接将被终止。") }
    }
}

private struct SessionTab: View {
    @ObservedObject var session: TerminalSession
    var selected: Bool
    var select: () -> Void
    var close: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Button(action: select) {
                HStack(spacing: 7) { Image(systemName: session.kind.symbol); Text(session.title).lineLimit(1).frame(maxWidth: 160) }
                    .frame(height: 38).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 8)).frame(width: 16, height: 24) }.buttonStyle(.plain).help("关闭会话")
        }.font(.system(size: 11)).padding(.horizontal, 13).foregroundStyle(selected ? Theme.accent : Color.secondary)
            .background(selected ? Theme.canvas : Color.clear)
            .overlay(alignment: .top) { if selected { Rectangle().fill(Theme.accent).frame(height: 2) } }
            .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
    }
}

private struct TerminalPane: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var session: TerminalSession
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SessionStatus(session: session)
                Text(session.kind.host?.endpoint ?? "本机 · \(NSUserName())").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer()
                if session.isLogging { Label("录制中", systemImage: "record.circle").foregroundStyle(.orange).font(.system(size: 10)) }
                Menu {
                    Button("导出终端文本…") { session.exportBuffer() }
                    Button(session.isLogging ? "停止会话日志" : "开始会话日志…") { session.toggleLogging() }
                    Divider()
                    Button("增大字体") { session.changeFont(by: 1) }
                    Button("减小字体") { session.changeFont(by: -1) }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 20)
            }.padding(.horizontal, 13).frame(height: 31).background(Color(nsColor: Theme.terminal))
            TerminalSurface(session: session).padding(.horizontal, 12).padding(.bottom, 7).background(Color(nsColor: Theme.terminal))
            if session.state == .ended {
                HStack {
                    Text("会话已结束\(session.exitCode.map { " · 退出码 \($0)" } ?? "")").foregroundStyle(.secondary)
                    Spacer()
                    Button("重新连接") { let kind = session.kind; store.closeSession(session); store.openSession(kind: kind) }.buttonStyle(ActionButtonStyle(primary: true))
                }.padding(12).background(Theme.panel)
            }
            HStack {
                Text(session.directory).lineLimit(1); Spacer(); Text("UTF-8"); Text("xterm-256color"); Text(session.dimensions)
            }.font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.muted).padding(.horizontal, 12).frame(height: 23).background(Theme.panel)
        }
    }
}

private struct SessionInspector: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var session: TerminalSession
    @State private var metrics = ""
    @State private var loading = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("会话信息").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted)
                    Label(session.kind.title, systemImage: session.kind.symbol).font(.system(size: 13, weight: .medium)).lineLimit(2)
                    SessionStatus(session: session)
                    Divider()
                    info("主机", session.kind.host?.address ?? Foundation.Host.current().localizedName ?? "localhost")
                    info("用户", session.kind.host?.username ?? NSUserName())
                    info("协议", session.kind.host == nil ? "本地 Shell" : "SSH 2")
                    info("认证", session.kind.host?.identityFile.isEmpty == false ? "SSH 私钥" : "交互 / 系统密钥")
                    info("启动", session.startedAt.formatted(date: .omitted, time: .shortened))
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("系统概况").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted); Spacer()
                        IconButton(symbol: "arrow.clockwise", help: "读取系统概况") { Task { await refreshMetrics() } }.disabled(loading || session.state != .running)
                    }
                    if loading { ProgressView().controlSize(.small) }
                    Text(metrics.isEmpty ? "点击刷新，读取系统版本、负载与磁盘用量。" : metrics)
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineSpacing(4).textSelection(.enabled)
                }
                Divider()
                VStack(alignment: .leading, spacing: 9) {
                    Text("快捷命令").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted)
                    ForEach(store.document.snippets.prefix(6)) { snippet in
                        Button { session.insert(snippet.command) } label: {
                            HStack { Image(systemName: "bolt").foregroundStyle(Theme.accent); Text(snippet.title).lineLimit(1); Spacer(); Image(systemName: "arrow.turn.down.left").foregroundStyle(Theme.muted) }
                                .padding(9).background(Theme.elevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                        }.buttonStyle(.plain).disabled(session.state == .ended).help("插入命令，按回车执行")
                    }
                    Text("插入后按回车执行").font(.system(size: 9)).foregroundStyle(Theme.muted)
                }
            }.padding(16)
        }.background(Theme.sidebar)
    }
    private func info(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) { Text(label).foregroundStyle(Theme.muted).frame(width: 33, alignment: .leading); Text(value).foregroundStyle(.secondary).textSelection(.enabled); Spacer(minLength: 0) }.font(.system(size: 10))
    }
    private func refreshMetrics() async {
        loading = true; defer { loading = false }
        do {
            let result: CommandResult
            let command = "uname -srm; printf '\\n'; uptime; printf '\\n'; df -h / | tail -1"
            if let host = session.kind.host {
                result = try await ProcessRunner.run("/usr/bin/ssh", SSHCommand.multiplexArguments(for: host, socket: session.socketPath) + [command], timeout: 10)
            } else { result = try await ProcessRunner.run("/bin/sh", ["-c", command], timeout: 10) }
            metrics = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch { metrics = error.localizedDescription }
    }
}
