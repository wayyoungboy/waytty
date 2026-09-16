import AppKit
import SwiftUI
import TerminalCore

struct BrowserFile: Identifiable {
    var id: String { name }
    var name: String
    var size: Int64
    var isDirectory: Bool
    var isLink: Bool
    var permissions: String
    var modified: String
}

@MainActor
final class FileBrowserStore: ObservableObject {
    @Published var path: String
    @Published var files: [BrowserFile] = []
    @Published var busy = false
    @Published var error: String?
    @Published var showHidden = false
    @Published var operation = ""
    let session: TerminalSession
    var isRemote: Bool { session.kind.host != nil }

    init(session: TerminalSession) {
        self.session = session
        path = session.kind.host == nil ? FileManager.default.homeDirectoryForCurrentUser.path : "."
    }
    var visibleFiles: [BrowserFile] { files.filter { showHidden || !$0.name.hasPrefix(".") } }

    private func batch(_ commands: [String], timeout: TimeInterval = 30) async throws -> String {
        guard let host = session.kind.host, session.state == .running else { throw InputError.invalid("请先在终端完成 SSH 认证。") }
        let args = ["-F", "/dev/null", "-o", "ControlPath=\(session.socketPath)", "-o", "ControlMaster=no",
                    "-o", "ProxyCommand=/usr/bin/false", "-o", "BatchMode=yes", "-P", String(host.port),
                    "-b", "-", "\(host.username)@\(host.address.contains(":") ? "[\(host.address)]" : host.address)"]
        let result = try await ProcessRunner.run("/usr/bin/sftp", args, input: commands.joined(separator: "\n") + "\n", timeout: timeout)
        guard result.status == 0 else { throw InputError.invalid(String(result.output.suffix(2500))) }
        return result.output
    }

    func refresh(target: String? = nil) async {
        guard !busy else { return }
        busy = true; error = nil; operation = "读取目录…"
        defer { busy = false; operation = "" }
        do { try await load(target: target ?? path) }
        catch { self.error = error.localizedDescription }
    }
    private func load(target: String) async throws {
        if isRemote {
            let output = try await batch(["cd \(SFTP.quote(target))", "pwd", "ls -la"])
            guard let line = output.components(separatedBy: .newlines).first(where: { $0.hasPrefix("Remote working directory: ") }) else {
                throw InputError.invalid("无法解析 SFTP 当前目录。")
            }
            path = String(line.dropFirst("Remote working directory: ".count))
            files = SFTP.parseListing(output).map { BrowserFile(name: $0.name, size: $0.size, isDirectory: $0.isDirectory, isLink: $0.isLink, permissions: $0.permissions, modified: $0.modified) }
        } else {
            let url = URL(fileURLWithPath: (target as NSString).expandingTildeInPath).standardizedFileURL
            let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
            let result = try urls.map { item -> BrowserFile in
                let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
                return BrowserFile(name: item.lastPathComponent, size: Int64(values.fileSize ?? 0), isDirectory: values.isDirectory ?? false,
                                   isLink: values.isSymbolicLink ?? false, permissions: "", modified: values.contentModificationDate?.formatted(date: .abbreviated, time: .shortened) ?? "")
            }
            path = url.path
            files = result.sorted { a, b in a.isDirectory != b.isDirectory ? a.isDirectory : a.name.localizedStandardCompare(b.name) == .orderedAscending }
        }
    }
    func open(_ file: BrowserFile) async {
        if file.isDirectory || (isRemote && file.isLink) { await refresh(target: SFTP.joined(path, file.name)) }
        else if !isRemote { NSWorkspace.shared.open(URL(fileURLWithPath: SFTP.joined(path, file.name))) }
        else { await download(file) }
    }
    func parent() async {
        let target = (path as NSString).deletingLastPathComponent
        await refresh(target: target.isEmpty ? "/" : target)
    }
    func createDirectory(_ name: String) async {
        guard !busy else { return }
        busy = true; error = nil; operation = "创建目录…"; defer { busy = false; operation = "" }
        do {
            try validName(name)
            if isRemote { _ = try await batch(["mkdir \(SFTP.quote(SFTP.joined(path, name)))"]) }
            else { try FileManager.default.createDirectory(atPath: SFTP.joined(path, name), withIntermediateDirectories: false) }
            try await load(target: path)
        } catch { self.error = error.localizedDescription }
    }
    func rename(_ file: BrowserFile, to name: String) async {
        guard !busy else { return }
        busy = true; error = nil; operation = "重命名…"; defer { busy = false; operation = "" }
        do {
            try validName(name)
            guard !files.contains(where: { $0.name == name }) else { throw InputError.invalid("同名文件已存在。") }
            if isRemote { _ = try await batch(["rename \(SFTP.quote(SFTP.joined(path, file.name))) \(SFTP.quote(SFTP.joined(path, name)))"]) }
            else { try FileManager.default.moveItem(atPath: SFTP.joined(path, file.name), toPath: SFTP.joined(path, name)) }
            try await load(target: path)
        } catch { self.error = error.localizedDescription }
    }
    func remove(_ file: BrowserFile) async {
        guard !busy else { return }
        busy = true; error = nil; operation = "删除…"; defer { busy = false; operation = "" }
        do {
            if isRemote { _ = try await batch(["\(file.isDirectory ? "rmdir" : "rm") \(SFTP.quote(SFTP.joined(path, file.name)))"]) }
            else { _ = try FileManager.default.trashItem(at: URL(fileURLWithPath: SFTP.joined(path, file.name)), resultingItemURL: nil) }
            try await load(target: path)
        } catch { self.error = error.localizedDescription }
    }
    func upload() async {
        guard isRemote, !busy else { return }
        let panel = NSOpenPanel(); panel.title = "上传文件"; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        // Refuse collisions instead of silently overwriting remote data.
        guard !urls.contains(where: { url in files.contains(where: { $0.name == url.lastPathComponent }) }) else { error = "目标目录已有同名文件，请先重命名后上传。"; return }
        busy = true; error = nil; operation = "上传 \(urls.count) 个文件…"; defer { busy = false; operation = "" }
        do {
            for url in urls { _ = try await batch(["put \(SFTP.quote(url.path)) \(SFTP.quote(SFTP.joined(path, url.lastPathComponent)))"], timeout: 600) }
            try await load(target: path)
        } catch { self.error = error.localizedDescription }
    }
    func download(_ file: BrowserFile) async {
        guard isRemote, !busy, !file.isDirectory else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = file.name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; error = nil; operation = "下载 \(file.name)…"; defer { busy = false; operation = "" }
        // Download to a sibling temporary file before replacing a user-approved destination.
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".waytty-download-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            _ = try await batch(["get \(SFTP.quote(SFTP.joined(path, file.name))) \(SFTP.quote(temporary.path))"], timeout: 600)
            if FileManager.default.fileExists(atPath: url.path) { _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary) }
            else { try FileManager.default.moveItem(at: temporary, to: url) }
        } catch { self.error = error.localizedDescription }
    }
    private func validName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(where: { $0.isNewline || $0 == "\0" }) else {
            throw InputError.invalid("请输入不包含斜杠或换行的文件名称。")
        }
    }
}
