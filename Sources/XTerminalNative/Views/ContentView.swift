import SwiftUI
import TerminalCore

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var groupName = ""

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Rectangle().fill(Theme.line).frame(height: 1)
            switch store.page {
            case .connections: ConnectionWorkspace()
            case .terminal: TerminalWorkspace()
            case .notes: NotesView()
            case .snippets: SnippetsView()
            }
            statusBar
        }
        .font(.system(size: 12)).background(Theme.canvas).ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 1060, minHeight: 650)
        .sheet(item: $store.editingHost) { host in HostEditor(host: host).environmentObject(store) }
        .sheet(item: $store.editingTunnel) { tunnel in TunnelEditor(tunnel: tunnel).environmentObject(store) }
        .alert("新建分组", isPresented: $store.showingNewGroup) {
            TextField("分组名称", text: $groupName)
            Button("取消", role: .cancel) { groupName = "" }
            Button("创建") { store.addGroup(groupName); groupName = "" }
        }
        .alert("操作未完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("知道了", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .alert("导入结果", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("完成", role: .cancel) { store.message = nil }
        } message: { Text(store.message ?? "") }
    }

    private var topBar: some View {
        HStack(spacing: 7) {
            Color.clear.frame(width: 72, height: 1)
            ForEach(WorkspacePage.allCases, id: \.self) { page in
                Button {
                    if page == .terminal && store.sessions.isEmpty { store.newLocalTerminal() }
                    store.page = page
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: page.symbol).font(.system(size: 13, weight: .medium))
                        if store.page == page { Text(page.rawValue).font(.system(size: 11, weight: .medium)) }
                    }
                    .foregroundStyle(store.page == page ? Theme.accent : Color.secondary)
                    .padding(.horizontal, 11).frame(height: 29)
                    .background(store.page == page ? Theme.canvas : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).help(page.rawValue).accessibilityLabel(page.rawValue)
            }
            Spacer()
            Text("XTerminal").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            Text("NATIVE").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.4).foregroundStyle(Theme.accent)
                .padding(.horizontal, 6).padding(.vertical, 3).background(Theme.accent.opacity(0.08), in: Capsule())
            Spacer()
            Button { store.newLocalTerminal() } label: { Image(systemName: "plus") }.buttonStyle(.plain).help("新建本地终端 ⌘T")
            SettingsLink { Image(systemName: "gearshape").frame(width: 28, height: 28) }.buttonStyle(.plain).help("设置 ⌘,")
        }
        .padding(.horizontal, 12).frame(height: 45).background(Theme.elevated)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "internaldrive").foregroundStyle(Theme.accent)
            Text("本地仓库").foregroundStyle(.secondary)
            Rectangle().fill(Theme.line).frame(width: 1, height: 10).padding(.horizontal, 4)
            Text("\(store.document.hosts.count) 个连接").foregroundStyle(Theme.muted)
            Spacer()
            if !store.sessions.isEmpty { Text("\(store.sessions.count) 个会话").foregroundStyle(.secondary) }
            Text("macOS 原生 · SwiftUI / AppKit").foregroundStyle(Theme.muted)
        }.font(.system(size: 10)).padding(.horizontal, 15).frame(height: 26)
            .background(Theme.sidebar).overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

struct ConnectionWorkspace: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 26) {
                ForEach(ConnectionSection.allCases, id: \.self) { section in
                    Button { store.section = section } label: {
                        Text(section.rawValue).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(store.section == section ? Theme.accent : Color.secondary)
                            .frame(height: 40)
                            .overlay(alignment: .bottom) { if store.section == section { Rectangle().fill(Theme.accent).frame(height: 2) } }
                    }.buttonStyle(.plain)
                }
                Spacer()
                Menu {
                    Button("SSH Config…", action: store.importSSHConfig)
                    Button("原生版仓库 JSON…", action: store.importWorkspace)
                } label: { Label("导入", systemImage: "square.and.arrow.down") }
                    .menuStyle(.borderlessButton).fixedSize()
                Button(action: store.exportWorkspace) { Label("导出", systemImage: "square.and.arrow.up") }.buttonStyle(ActionButtonStyle())
            }.padding(.horizontal, 18).background(Theme.canvas)
            Rectangle().fill(Theme.line).frame(height: 1)
            switch store.section {
            case .ssh:
                HStack(spacing: 0) {
                    if store.sidebarVisible { SidebarView().frame(width: 224); Rectangle().fill(Theme.line).frame(width: 1) }
                    HostListView()
                }
            case .tunnels: TunnelListView()
            case .vnc: VNCView()
            }
        }
    }
}
