import Foundation
import TerminalCore

typealias Host = TerminalCore.Host

enum WorkspacePage: String, CaseIterable {
    case connections = "连接管理", terminal = "控制台", notes = "笔记", snippets = "命令库"
    var symbol: String {
        switch self { case .connections: return "link"; case .terminal: return "terminal"; case .notes: return "book.closed"; case .snippets: return "bolt" }
    }
}

enum HostFilter: Hashable {
    case all, favorites, recent, group(String)
    var title: String {
        switch self { case .all: return "全部连接"; case .favorites: return "收藏"; case .recent: return "最近使用"; case .group(let name): return name }
    }
}

enum ConnectionSection: String, CaseIterable {
    case ssh = "SSH", tunnels = "隧道", vnc = "VNC"
}
