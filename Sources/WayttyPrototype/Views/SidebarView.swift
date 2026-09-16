import SwiftUI
import TerminalCore

struct SidebarView: View {
    @EnvironmentObject var store: AppStore
    @State private var expanded = Set(["开发环境", "生产环境", "未分组", "SSH Config"])
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                IconButton(symbol: "sidebar.left", help: "收起侧栏") { store.sidebarVisible = false }
                Spacer()
                Button { store.showingNewGroup = true } label: { Label("分组", systemImage: "plus") }.buttonStyle(ActionButtonStyle())
                IconButton(symbol: "plus", help: "新建 SSH 连接") { store.newHost() }
            }.padding(.horizontal, 9).frame(height: 47)
            Rectangle().fill(Theme.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    Text("连接仓库").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted).padding(.horizontal, 12).padding(.top, 18).padding(.bottom, 8)
                    filterRow(.all, symbol: "square.stack.3d.up", count: store.document.hosts.count)
                    filterRow(.favorites, symbol: "star", count: store.document.hosts.filter(\.favorite).count)
                    filterRow(.recent, symbol: "clock", count: store.document.hosts.filter { $0.lastConnected != nil }.count)
                    HStack { Text("我的分组"); Spacer(); Button { store.showingNewGroup = true } label: { Image(systemName: "plus") }.buttonStyle(.plain) }
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted).padding(.horizontal, 12).padding(.top, 26).padding(.bottom, 8)
                    ForEach(store.groups, id: \.self) { group in
                        groupRow(group)
                    }
                }.padding(.horizontal, 8)
            }
            Spacer(minLength: 0)
            Button { store.newLocalTerminal() } label: {
                HStack(spacing: 9) { Image(systemName: "terminal").foregroundStyle(Theme.accent); Text("打开本地终端"); Spacer(); Text("⌘T").foregroundStyle(Theme.muted) }
                    .padding(12).background(Theme.elevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain).padding(12)
        }.background(Theme.sidebar)
    }
    private func filterRow(_ filter: HostFilter, symbol: String, count: Int) -> some View {
        Button { store.filter = filter } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 15)
                Text(filter.title); Spacer()
                Text("\(count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
            }.foregroundStyle(store.filter == filter ? Theme.accent : Color.primary.opacity(0.78))
                .padding(.horizontal, 12).frame(height: 34)
                .background(store.filter == filter ? Theme.accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain)
    }
    private func groupRow(_ group: String) -> some View {
        let hosts = store.document.hosts.filter { $0.group == group }
        return VStack(spacing: 0) {
            HStack(spacing: 3) {
                Button { if expanded.contains(group) { expanded.remove(group) } else { expanded.insert(group) } } label: {
                    Image(systemName: expanded.contains(group) ? "chevron.down" : "chevron.right").font(.system(size: 8)).frame(width: 14, height: 30)
                }.buttonStyle(.plain).foregroundStyle(Theme.muted).accessibilityLabel("展开\(group)")
                Button { store.filter = .group(group) } label: {
                    HStack(spacing: 8) { Image(systemName: "folder"); Text(group).lineLimit(1); Spacer(); Text("\(hosts.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted) }
                        .frame(height: 32).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.padding(.leading, 6).padding(.trailing, 12)
                .foregroundStyle(store.filter == .group(group) ? Theme.accent : Color.primary.opacity(0.75))
                .background(store.filter == .group(group) ? Theme.accent.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .contextMenu {
                    Button("新建 SSH 连接") { store.filter = .group(group); store.newHost() }
                    Button("移除分组，连接移至未分组") { store.removeGroup(group) }
                }
            if expanded.contains(group) {
                ForEach(hosts) { host in
                    Button { store.connect(host) } label: {
                        HStack(spacing: 8) { Rectangle().fill(Theme.line).frame(width: 1, height: 27); Text(host.name).lineLimit(1); Spacer() }
                            .padding(.leading, 28).padding(.trailing, 12).foregroundStyle(.secondary)
                    }.buttonStyle(.plain).help("连接 \(host.endpoint)")
                }
            }
        }
    }
}
