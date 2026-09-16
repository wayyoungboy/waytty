import SwiftUI
import TerminalCore

struct HostListView: View {
    @EnvironmentObject var store: AppStore
    @State private var selected: UUID?
    @State private var deletingHost: Host?
    @State private var showInfo = true
    @State private var ascending = true
    @FocusState private var searchFocused: Bool
    var hosts: [Host] { ascending ? store.visibleHosts : store.visibleHosts.reversed() }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if !store.sidebarVisible { IconButton(symbol: "sidebar.left", help: "显示侧栏") { store.sidebarVisible = true } }
                Text(store.filter.title).font(.system(size: 12, weight: .medium))
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("搜索名称、地址、用户…", text: $store.search).textFieldStyle(.plain).focused($searchFocused)
                    if !store.search.isEmpty { Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
                }.padding(.horizontal, 9).frame(width: 250, height: 28).background(Theme.panel, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.line))
                Spacer(minLength: 8)
                IconButton(symbol: "eye", help: "显示连接信息", active: showInfo) { showInfo.toggle() }
                Button { store.newHost() } label: { Label("SSH", systemImage: "plus") }.buttonStyle(ActionButtonStyle(primary: true))
                Badge(text: "本地仓库", color: Theme.accent)
            }.padding(.horizontal, 16).frame(height: 47)
            tableHeader
            if hosts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(hosts) { host in
                            HostRow(host: host, showInfo: showInfo, selected: selected == host.id,
                                    select: { selected = host.id }, delete: { deletingHost = host })
                        }
                    }
                }
                HStack {
                    Text("\(hosts.count) 个连接"); Spacer()
                    Text("双击连接 · 右键更多操作")
                }.font(.system(size: 10)).foregroundStyle(Theme.muted).padding(14)
            }
        }
        .alert("删除连接？", isPresented: Binding(get: { deletingHost != nil }, set: { if !$0 { deletingHost = nil } })) {
            Button("取消", role: .cancel) { deletingHost = nil }
            Button("删除", role: .destructive) { if let host = deletingHost { store.deleteHost(host) }; deletingHost = nil }
        } message: { Text("连接“\(deletingHost?.name ?? "")”及关联隧道配置将从本地仓库移除。") }
        .onExitCommand { store.search = "" }
    }
    private var tableHeader: some View {
        HStack(spacing: 0) {
            Image(systemName: "star").frame(width: 42)
            Text("系统").frame(width: 60, alignment: .leading)
            Text("状态").frame(width: 90, alignment: .leading)
            Button { ascending.toggle() } label: { HStack(spacing: 6) { Text("名称"); Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 8)) } }
                .buttonStyle(.plain).frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
            Text("地址").frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
            if showInfo { Text("信息").frame(width: 126, alignment: .leading) }
            Text("操作").frame(width: 142, alignment: .leading)
        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 8).frame(height: 37)
            .background(Theme.panel.opacity(0.5))
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: store.search.isEmpty ? "server.rack" : "magnifyingglass").font(.system(size: 42, weight: .ultraLight))
                .foregroundStyle(Theme.accent.opacity(0.8)).frame(width: 86, height: 86)
                .background(Theme.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.accent.opacity(0.12)))
            VStack(spacing: 9) {
                Text(store.search.isEmpty ? "每一次连接，都从这里开始" : "没有找到匹配的连接").font(.system(size: 19, weight: .medium))
                Text(store.search.isEmpty ? "管理服务器、打开终端，让工作井然有序。" : "尝试其他名称、地址或用户。").foregroundStyle(.secondary)
            }
            if store.search.isEmpty {
                HStack(spacing: 10) {
                    Button { store.newHost() } label: { Label("新建 SSH 连接", systemImage: "plus") }.buttonStyle(ActionButtonStyle(primary: true))
                    Button(action: store.importSSHConfig) { Label("导入 SSH Config", systemImage: "square.and.arrow.down") }.buttonStyle(ActionButtonStyle())
                }.padding(.top, 5)
                Button("或打开本地终端  ⌘T") { store.newLocalTerminal() }.buttonStyle(.plain).foregroundStyle(Theme.muted).padding(.top, 4)
            } else { Button("清除搜索") { store.search = "" }.buttonStyle(ActionButtonStyle()) }
            Spacer()
            HStack(spacing: 26) {
                Label("本地保存", systemImage: "internaldrive")
                Label("系统 SSH", systemImage: "lock.shield")
                Label("原生终端", systemImage: "terminal")
            }.font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.bottom, 28)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HostRow: View {
    @EnvironmentObject var store: AppStore
    let host: Host
    let showInfo: Bool
    let selected: Bool
    let select: () -> Void
    let delete: () -> Void
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 0) {
            Button { store.toggleFavorite(host) } label: {
                Image(systemName: host.favorite ? "star.fill" : "star").foregroundStyle(host.favorite ? Color.yellow.opacity(0.85) : Theme.muted).frame(width: 42, height: 44)
            }.buttonStyle(.plain).help(host.favorite ? "取消收藏" : "加入收藏")
            SystemIcon(system: host.system).frame(width: 60, alignment: .leading)
            HostConnectionStatus(hostID: host.id).frame(width: 90, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(host.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(host.group).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
            }.frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 5) {
                Text(host.port == 22 ? host.address : "\(host.address):\(host.port)").font(.system(size: 11, design: .monospaced)).lineLimit(1).foregroundStyle(.secondary)
                Button { copyToClipboard(host.address) } label: { Image(systemName: "doc.on.doc").font(.system(size: 10)).foregroundStyle(Theme.accent.opacity(0.7)) }.buttonStyle(.plain).help("复制地址")
            }.frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
            if showInfo {
                HStack(spacing: 4) { Badge(text: host.username); Image(systemName: host.identityFile.isEmpty ? "person.badge.key" : "key").font(.system(size: 10)).foregroundStyle(Theme.muted) }
                    .frame(width: 126, alignment: .leading)
            }
            HStack(spacing: 10) {
                Button("连接") { store.connect(host) }.buttonStyle(ActionButtonStyle(primary: true))
                Button("编辑") { store.editingHost = host }.buttonStyle(.plain).foregroundStyle(.secondary)
                Menu {
                    Button("复制 SSH 命令") { if let args = try? SSHCommand.arguments(for: host) { copyToClipboard(SSHCommand.display(args)) } }
                    Button("复制连接", action: { store.duplicate(host) })
                    Divider()
                    Button("删除连接", role: .destructive, action: delete)
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 16)
            }.frame(width: 142, alignment: .leading)
        }.padding(.horizontal, 8).frame(height: 61)
            .background(selected ? Theme.accent.opacity(0.06) : (hovering ? Color.white.opacity(0.025) : Color.clear))
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            .contentShape(Rectangle()).onHover { hovering = $0 }
            .onTapGesture(count: 2) { store.connect(host) }.onTapGesture(perform: select)
            .contextMenu {
                Button("连接") { store.connect(host) }
                Button("编辑") { store.editingHost = host }
                Button("复制") { store.duplicate(host) }
                Button(host.favorite ? "取消收藏" : "加入收藏") { store.toggleFavorite(host) }
                Divider(); Button("删除", role: .destructive, action: delete)
            }
    }
}

struct HostConnectionStatus: View {
    @EnvironmentObject var store: AppStore
    var hostID: UUID
    var body: some View {
        if let session = store.sessions.last(where: { $0.kind.host?.id == hostID }) { SessionStatus(session: session, compact: true) }
        else { Text("未连接").font(.system(size: 10)).foregroundStyle(Theme.muted) }
    }
}

struct SessionStatus: View {
    @ObservedObject var session: TerminalSession
    var compact = false
    var color: Color { session.state == .running ? Theme.accent : (session.state == .starting ? .orange : Theme.muted) }
    var body: some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 5, height: 5); Text(session.state.rawValue).font(.system(size: compact ? 10 : 11)).foregroundStyle(color) }
    }
}

struct SystemIcon: View {
    var system: String
    var color: Color { switch system { case "Ubuntu": return .orange; case "Debian": return .pink; case "macOS": return .white; default: return Theme.accent } }
    var body: some View {
        Image(systemName: system == "macOS" ? "apple.logo" : (system == "Ubuntu" ? "circle.hexagongrid" : "server.rack"))
            .font(.system(size: 15)).foregroundStyle(color.opacity(0.85)).frame(width: 29, height: 29)
            .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(color.opacity(0.12)))
            .help(system)
    }
}
