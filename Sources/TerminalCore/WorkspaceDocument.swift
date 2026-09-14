import Foundation

public struct Snippet: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var title: String
    public var command: String
    public init(title: String, command: String) { self.title = title; self.command = command }
}

public struct Note: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var title: String
    public var body: String
    public init(title: String = "未命名笔记", body: String = "") { self.title = title; self.body = body }
}

public struct WorkspaceDocument: Codable, Equatable, Sendable {
    public var version = 1
    public var hosts: [Host] = []
    public var groups = ["开发环境", "生产环境"]
    public var tunnels: [Tunnel] = []
    public var snippets = [
        Snippet(title: "系统信息", command: "uname -a"),
        Snippet(title: "磁盘用量", command: "df -h"),
        Snippet(title: "当前进程", command: "ps aux"),
        Snippet(title: "监听端口 · macOS", command: "lsof -nP -iTCP -sTCP:LISTEN"),
        Snippet(title: "监听端口 · Linux", command: "ss -tlnp")
    ]
    public var notes: [Note] = []
    public init() {}

    public func validate() throws {
        guard version == 1 else { throw InputError.invalid("无法读取此版本的仓库文件。") }
        guard Set(hosts.map(\.id)).count == hosts.count,
              Set(tunnels.map(\.id)).count == tunnels.count,
              Set(snippets.map(\.id)).count == snippets.count,
              Set(notes.map(\.id)).count == notes.count else { throw InputError.invalid("仓库包含重复 ID。") }
        for host in hosts { _ = try host.validated() }
        for tunnel in tunnels { try tunnel.validate() }
    }
}
