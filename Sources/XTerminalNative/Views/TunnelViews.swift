import SwiftUI
import TerminalCore

struct TunnelListView: View {
    @EnvironmentObject var store: AppStore
    @State private var deleting: Tunnel?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("端口转发").font(.system(size: 21, weight: .medium))
                    Text("通过 SSH 安全地访问远程服务。支持本地、远程和 SOCKS5 转发。").foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.editingTunnel = Tunnel() } label: { Label("新建隧道", systemImage: "plus") }.buttonStyle(ActionButtonStyle(primary: true)).disabled(store.document.hosts.isEmpty)
            }.padding(28)
            Divider()
            if store.document.tunnels.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(Theme.accent)
                    Text("让远程服务，触手可及").font(.system(size: 19, weight: .medium))
                    Text(store.document.hosts.isEmpty ? "先添加 SSH 连接，再创建端口转发。" : "将数据库、开发服务或网络代理连接到本地端口。").foregroundStyle(.secondary)
                    Button(store.document.hosts.isEmpty ? "添加 SSH 连接" : "创建第一个隧道") {
                        if store.document.hosts.isEmpty { store.newHost() } else { store.editingTunnel = Tunnel() }
                    }.buttonStyle(ActionButtonStyle(primary: true))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.document.tunnels) { tunnel in
                            HStack(spacing: 20) {
                                Image(systemName: "arrow.triangle.branch").font(.system(size: 20)).foregroundStyle(Theme.accent).frame(width: 36)
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack { Text(tunnel.name).font(.system(size: 14, weight: .medium)); Badge(text: tunnel.kind.rawValue) }
                                    Text("127.0.0.1:\(tunnel.bindPort)  →  \(tunnel.kind == .dynamic ? "SOCKS5" : "\(tunnel.destination):\(tunnel.destinationPort)")")
                                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(store.document.hosts.first { $0.id == tunnel.hostID }?.name ?? "主机已移除").foregroundStyle(.secondary)
                                if let session = store.sessions.last(where: { $0.kind.tunnelID == tunnel.id }) { TunnelStateControls(session: session) }
                                else { Button("启动") { store.startTunnel(tunnel) }.buttonStyle(ActionButtonStyle(primary: true)) }
                                Button("编辑") { store.editingTunnel = tunnel }.buttonStyle(ActionButtonStyle())
                                IconButton(symbol: "trash", help: "删除隧道") { deleting = tunnel }
                            }.padding(20).background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
                        }
                    }.padding(24)
                }
            }
        }.alert("删除隧道配置？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除", role: .destructive) {
                if let tunnel = deleting {
                    for session in store.sessions.filter({ $0.kind.tunnelID == tunnel.id }) { store.closeSession(session) }
                    store.document.tunnels.removeAll { $0.id == tunnel.id }; store.save()
                }
                deleting = nil
            }
        } message: { Text("关联的转发会话也将停止。") }
    }
}

private struct TunnelStateControls: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var session: TerminalSession
    var body: some View {
        HStack(spacing: 12) {
            SessionStatus(session: session)
            if session.state != .ended {
                Button("停止") { store.closeSession(session) }.buttonStyle(ActionButtonStyle())
                Button("终端") { store.activeSessionID = session.id; store.page = .terminal }.buttonStyle(ActionButtonStyle())
            } else { Button("重新启动") { let kind = session.kind; store.closeSession(session); store.openSession(kind: kind) }.buttonStyle(ActionButtonStyle(primary: true)) }
        }
    }
}

struct TunnelEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State var tunnel: Tunnel
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("配置 SSH 隧道", systemImage: "arrow.triangle.branch").font(.system(size: 17, weight: .medium))
            editorGroup {
                editorRow("名称") { TextField("开发数据库", text: $tunnel.name) }
                editorRow("SSH 连接") {
                    Picker("SSH 连接", selection: $tunnel.hostID) {
                        Text("选择连接").tag(Optional<UUID>.none)
                        ForEach(store.document.hosts) { Text($0.name).tag(Optional($0.id)) }
                    }.labelsHidden()
                }
                editorRow("转发方式") { Picker("方式", selection: $tunnel.kind) { ForEach(ForwardKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden() }
                editorRow(tunnel.kind == .remote ? "远程监听端口" : "本地监听端口") { TextField("8080", value: $tunnel.bindPort, formatter: NumberFormatter.port) }
                if tunnel.kind != .dynamic {
                    editorRow("目标地址") { TextField("127.0.0.1", text: $tunnel.destination) }
                    editorRow("目标端口") { TextField("80", value: $tunnel.destinationPort, formatter: NumberFormatter.port) }
                }
            }
            Text(tunnel.kind == .remote ? "远程主机的监听端口转发到本机可访问的目标服务。" : "监听地址固定为 127.0.0.1，仅允许本机访问。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.orange).font(.system(size: 11)) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(ActionButtonStyle()).keyboardShortcut(.cancelAction)
                Button("保存") { do { try store.saveTunnel(tunnel); dismiss() } catch { self.error = error.localizedDescription } }
                    .buttonStyle(ActionButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 580).background(Theme.elevated).preferredColorScheme(.dark)
            .onAppear { if tunnel.hostID == nil { tunnel.hostID = store.document.hosts.first?.id } }
    }
}

struct VNCView: View {
    @State private var address = ""
    @State private var port = "5900"
    @State private var error: String?
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "display.2").font(.system(size: 45, weight: .ultraLight)).foregroundStyle(Theme.accent)
            Text("屏幕共享").font(.system(size: 23, weight: .medium))
            Text("使用 macOS 自带的屏幕共享连接 VNC 服务器。").foregroundStyle(.secondary)
            HStack { TextField("主机地址", text: $address); TextField("5900", text: $port).frame(width: 75) }.textFieldStyle(.roundedBorder).frame(width: 400)
            Button("打开屏幕共享") {
                guard Host.validAddress(address), let number = Int(port), (1...65535).contains(number) else { error = "请输入有效的主机地址和端口。"; return }
                var parts = URLComponents(); parts.scheme = "vnc"; parts.host = address; parts.port = number
                guard let url = parts.url, NSWorkspace.shared.open(url) else { error = "无法打开屏幕共享。"; return }; error = nil
            }.buttonStyle(ActionButtonStyle(primary: true))
            if let error { Text(error).foregroundStyle(.orange) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
