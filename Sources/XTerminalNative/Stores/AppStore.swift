import AppKit
import SwiftUI
import TerminalCore
import UniformTypeIdentifiers

@MainActor
final class AppStore: ObservableObject {
    @Published var document = WorkspaceDocument()
    @Published var page: WorkspacePage = .connections
    @Published var section: ConnectionSection = .ssh
    @Published var filter: HostFilter = .all
    @Published var search = ""
    @Published var sessions: [TerminalSession] = []
    @Published var activeSessionID: UUID?
    @Published var splitSessionID: UUID?
    @Published var editingHost: Host?
    @Published var editingTunnel: Tunnel?
    @Published var showingNewGroup = false
    @Published var error: String?
    @Published var message: String?
    @Published var showFiles = false
    @Published var showInspector = true
    @Published var sidebarVisible = true
    let storageURL: URL
    let socketDirectory: URL
    private var canSave = true

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("XTerminalNative/workspace.json")
        socketDirectory = URL(fileURLWithPath: "/tmp/xtn-\(getuid())-\(UUID().uuidString.prefix(8))")
        do {
            try FileManager.default.createDirectory(at: socketDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if FileManager.default.fileExists(atPath: self.storageURL.path) {
                document = try JSONDecoder().decode(WorkspaceDocument.self, from: Data(contentsOf: self.storageURL))
                try document.validate()
            }
        } catch { self.error = "读取仓库失败，原文件已保留：\(error.localizedDescription)"; canSave = false }
    }

    var groups: [String] { Array(Set(document.groups + document.hosts.map(\.group))).sorted() }
    var activeSession: TerminalSession? { sessions.first { $0.id == activeSessionID } }
    var visibleHosts: [Host] {
        document.hosts.filter { host in
            let matches: Bool
            switch filter {
            case .all: matches = true
            case .favorites: matches = host.favorite
            case .recent: matches = host.lastConnected != nil
            case .group(let name): matches = host.group == name
            }
            return matches && (search.isEmpty || [host.name, host.address, host.username, host.group, host.notes].joined(separator: " ").localizedCaseInsensitiveContains(search))
        }.sorted { a, b in
            if filter == .recent { return (a.lastConnected ?? .distantPast) > (b.lastConnected ?? .distantPast) }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    func save() {
        guard canSave else { error = "仓库读取失败；为保留原文件，本次修改无法保存。请先备份并修复仓库文件。"; return }
        do {
            let directory = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: storageURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
        } catch { self.error = "保存失败：\(error.localizedDescription)" }
    }

    func saveHost(_ host: Host) throws {
        let host = try host.validated()
        if let i = document.hosts.firstIndex(where: { $0.id == host.id }) { document.hosts[i] = host }
        else { document.hosts.append(host) }
        if !document.groups.contains(host.group) { document.groups.append(host.group) }
        save()
    }
    func newHost() {
        var host = Host()
        if case .group(let name) = filter { host.group = name }
        editingHost = host
    }
    func toggleFavorite(_ host: Host) {
        if let i = document.hosts.firstIndex(where: { $0.id == host.id }) { document.hosts[i].favorite.toggle(); save() }
    }
    func duplicate(_ host: Host) { var copy = host; copy.id = UUID(); copy.name += " - 副本"; copy.lastConnected = nil; editingHost = copy }
    func deleteHost(_ host: Host) {
        document.hosts.removeAll { $0.id == host.id }
        document.tunnels.removeAll { $0.hostID == host.id }
        save()
    }
    func addGroup(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if !groups.contains(name) { document.groups.append(name); save() }
        filter = .group(name)
    }
    func removeGroup(_ group: String) {
        document.groups.removeAll { $0 == group }
        for i in document.hosts.indices where document.hosts[i].group == group { document.hosts[i].group = "未分组" }
        filter = .all; save()
    }

    func newLocalTerminal() { openSession(kind: .local) }
    func connect(_ host: Host) {
        do { _ = try host.validated(); openSession(kind: .ssh(host)) }
        catch { self.error = error.localizedDescription }
    }
    func openSession(kind: SessionKind) {
        let session = TerminalSession(kind: kind, socketDirectory: socketDirectory)
        session.onConnected = { [weak self] hostID in
            guard let self, let i = self.document.hosts.firstIndex(where: { $0.id == hostID }) else { return }
            self.document.hosts[i].lastConnected = Date(); self.save()
        }
        sessions.append(session); activeSessionID = session.id; page = .terminal
        session.start()
    }
    func closeSession(_ session: TerminalSession) {
        session.stop()
        sessions.removeAll { $0.id == session.id }
        if splitSessionID == session.id { splitSessionID = nil }
        if activeSessionID == session.id { activeSessionID = sessions.last?.id }
        if splitSessionID == activeSessionID { splitSessionID = nil }
    }
    func splitTerminal() {
        guard let active = activeSession else { return }
        if splitSessionID != nil { splitSessionID = nil; return }
        let previous = active.id
        openSession(kind: active.kind)
        splitSessionID = activeSessionID; activeSessionID = previous
    }
    func stopAll() {
        for session in sessions { session.stop() }
        try? FileManager.default.removeItem(at: socketDirectory)
    }
    func saveTunnel(_ tunnel: Tunnel) throws {
        try tunnel.validate()
        if let i = document.tunnels.firstIndex(where: { $0.id == tunnel.id }) { document.tunnels[i] = tunnel }
        else { document.tunnels.append(tunnel) }
        save()
    }
    func startTunnel(_ tunnel: Tunnel) {
        guard let host = document.hosts.first(where: { $0.id == tunnel.hostID }) else { error = "SSH 连接已不存在。"; return }
        if let existing = sessions.first(where: { $0.kind.tunnelID == tunnel.id && $0.state != .ended }) {
            activeSessionID = existing.id; page = .terminal; return
        }
        openSession(kind: .tunnel(host, tunnel))
    }

    func importSSHConfig() {
        let panel = NSOpenPanel(); panel.title = "导入 SSH Config"; panel.canChooseDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let result = SSHConfigImporter.parse(try String(contentsOf: url, encoding: .utf8))
            let newHosts = result.hosts.filter { h in !document.hosts.contains { $0.name == h.name && $0.endpoint == h.endpoint } }
            document.hosts.append(contentsOf: newHosts); save()
            filter = .all
            message = "已导入 \(newHosts.count) 个连接。" + (result.warnings.isEmpty ? "" : "\n\n" + result.warnings.joined(separator: "\n"))
        } catch { self.error = error.localizedDescription }
    }
    func importWorkspace() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.title = "合并导入原生版仓库"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try JSONDecoder().decode(WorkspaceDocument.self, from: Data(contentsOf: url)); try imported.validate()
            let ids = Set(document.hosts.map(\.id)); let additions = imported.hosts.filter { !ids.contains($0.id) }
            document.hosts += additions
            document.groups = Array(Set(document.groups + imported.groups)).sorted()
            document.tunnels += imported.tunnels.filter { t in !document.tunnels.contains { $0.id == t.id } }
            document.snippets += imported.snippets.filter { s in !document.snippets.contains { $0.id == s.id } }
            document.notes += imported.notes.filter { n in !document.notes.contains { $0.id == n.id } }
            save(); message = "已合并导入 \(additions.count) 个连接及命令、笔记和隧道。"
        } catch { self.error = "导入失败：\(error.localizedDescription)" }
    }
    func exportWorkspace() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "XTerminalNative-backup.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { self.error = error.localizedDescription }
    }
}
