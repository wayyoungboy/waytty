import AppKit
import SwiftUI
import SwiftTerm
import TerminalCore

enum SessionKind {
    case local, ssh(Host), tunnel(Host, Tunnel)
    var host: Host? { switch self { case .local: return nil; case .ssh(let h), .tunnel(let h, _): return h } }
    var tunnelID: UUID? { if case .tunnel(_, let tunnel) = self { return tunnel.id }; return nil }
    var title: String { switch self { case .local: return "本地终端"; case .ssh(let h): return h.name; case .tunnel(_, let t): return t.name } }
    var symbol: String { switch self { case .local: return "terminal"; case .ssh: return "network"; case .tunnel: return "arrow.triangle.branch" } }
}

enum SessionState: String { case starting = "等待认证", running = "已连接", ended = "已结束" }

/// Session lifetime owns the AppKit terminal. Switching SwiftUI tabs never recreates a PTY.
@MainActor
final class TerminalSession: NSObject, ObservableObject, Identifiable, LocalProcessTerminalViewDelegate {
    let id = UUID()
    let kind: SessionKind
    let socketPath: String
    let startedAt = Date()
    @Published var title: String
    @Published var state: SessionState = .starting
    @Published var directory = "~"
    @Published var dimensions = "80 × 24"
    @Published var exitCode: Int32?
    @Published var fontSize: Double
    @Published var isLogging = false
    var onConnected: ((UUID) -> Void)?
    private(set) var terminal: SafeTerminalView!
    private var connectionTask: Task<Void, Never>?
    private var delegateProxy: TerminalDelegateProxy?
    private var didStart = false

    init(kind: SessionKind, socketDirectory: URL) {
        self.kind = kind
        title = kind.title
        socketPath = socketDirectory.appendingPathComponent(UUID().uuidString).path
        let saved = UserDefaults.standard.double(forKey: "terminalFontSize")
        fontSize = saved > 0 ? saved : 13
        super.init()
        terminal = SafeTerminalView(frame: NSRect(x: 0, y: 0, width: 880, height: 520))
        terminal.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        terminal.nativeBackgroundColor = Theme.terminal
        terminal.nativeForegroundColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        terminal.caretColor = NSColor(red: 0.25, green: 0.76, blue: 0.52, alpha: 1)
        terminal.processDelegate = self
        delegateProxy = TerminalDelegateProxy(target: terminal)
        terminal.terminalDelegate = delegateProxy
    }

    func start() {
        guard !didStart else { return }; didStart = true
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"; env["COLORTERM"] = "truecolor"
        let unsupportedLocales = ["C", "POSIX", "C.UTF-8", "C.utf8"]
        if env["LANG"] == nil || unsupportedLocales.contains(env["LANG"] ?? "") { env["LANG"] = "en_US.UTF-8" }
        if unsupportedLocales.contains(env["LC_ALL"] ?? "") { env.removeValue(forKey: "LC_ALL") }
        if env["LC_CTYPE"] == nil || unsupportedLocales.contains(env["LC_CTYPE"] ?? "") { env["LC_CTYPE"] = "en_US.UTF-8" }
        // GUI launches often inherit a minimal PATH; preserve existing additions.
        env["PATH"] = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin") + ":/opt/homebrew/bin:/usr/local/bin"
        let environment = env.map { "\($0.key)=\($0.value)" }
        switch kind {
        case .local:
            let configured = UserDefaults.standard.string(forKey: "shellPath") ?? "/bin/zsh"
            let shell = FileManager.default.isExecutableFile(atPath: configured) ? configured : "/bin/zsh"
            terminal.startProcess(executable: shell, args: ["-l"], environment: environment,
                                  currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
            state = terminal.process.running ? .running : .ended
        case .ssh(let host), .tunnel(let host, _):
            do {
                let tunnel: Tunnel?
                if case .tunnel(_, let t) = kind { tunnel = t } else { tunnel = nil }
                let args = try SSHCommand.arguments(for: host, socket: socketPath, tunnel: tunnel)
                terminal.startProcess(executable: "/usr/bin/ssh", args: args, environment: environment,
                                      currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
                if !terminal.process.running { state = .ended; return }
                connectionTask = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard !Task.isCancelled, let self, self.state != .ended else { return }
                        if FileManager.default.fileExists(atPath: self.socketPath) {
                            self.state = .running; self.onConnected?(host.id)
                            if tunnel != nil { self.terminal.feed(text: "\r\n  隧道已建立。关闭标签页即可停止转发。\r\n") }
                            return
                        }
                    }
                }
            } catch { terminal.feed(text: "\r\n\(error.localizedDescription)\r\n"); state = .ended }
        }
    }

    func stop() {
        connectionTask?.cancel(); connectionTask = nil
        if isLogging { terminal.setHostLogging(directory: nil); isLogging = false }
        terminal.terminate(); state = .ended
        try? FileManager.default.removeItem(atPath: socketPath)
    }
    func insert(_ command: String) {
        guard state != .ended else { return }
        // Insert without Return: the user can review the command before executing it.
        terminal.send(txt: command)
        terminal.window?.makeFirstResponder(terminal)
    }
    func changeFont(by delta: Double) {
        fontSize = min(28, max(10, fontSize + delta))
        terminal.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
    func exportBuffer() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "terminal-\(Int(Date().timeIntervalSince1970)).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try terminal.getTerminal().getBufferAsData().write(to: url, options: .atomic) }
        catch { let alert = NSAlert(error: error); alert.runModal() }
    }
    func toggleLogging() {
        if isLogging { terminal.setHostLogging(directory: nil); isLogging = false; return }
        let panel = NSOpenPanel(); panel.title = "选择会话日志目录"; panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        terminal.setHostLogging(directory: url.path); isLogging = true
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        DispatchQueue.main.async { [weak self] in self?.dimensions = "\(newCols) × \(newRows)" }
    }
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        let cleaned = String(title.filter { !$0.isNewline }.prefix(60))
        DispatchQueue.main.async { [weak self] in if self?.kind.host == nil && !cleaned.isEmpty { self?.title = cleaned } }
    }
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory else { return }
        let path = URL(string: directory)?.path ?? directory
        DispatchQueue.main.async { [weak self] in self?.directory = path }
    }
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.exitCode = exitCode; self.state = .ended
            self.connectionTask?.cancel(); self.connectionTask = nil
            self.terminal.feed(text: "\r\n[会话已结束\(exitCode.map { " · 退出码 \($0)" } ?? "")]\r\n")
        }
    }
}

/// Remote terminal escape sequences must not read the clipboard or open arbitrary URL schemes.
final class SafeTerminalView: LocalProcessTerminalView {
    override func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Forward PTY, resize, and title events while denying OSC 52 clipboard access.
private final class TerminalDelegateProxy: TerminalViewDelegate {
    weak var target: LocalProcessTerminalView?
    init(target: LocalProcessTerminalView) { self.target = target }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { target?.sizeChanged(source: source, newCols: newCols, newRows: newRows) }
    func setTerminalTitle(source: TerminalView, title: String) { target?.setTerminalTitle(source: source, title: title) }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) { target?.hostCurrentDirectoryUpdate(source: source, directory: directory) }
    func send(source: TerminalView, data: ArraySlice<UInt8>) { target?.send(source: source, data: data) }
    func scrolled(source: TerminalView, position: Double) { target?.scrolled(source: source, position: position) }
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) { target?.requestOpenLink(source: source, link: link, params: params) }
    func bell(source: TerminalView) { NSSound.beep() }
    func clipboardCopy(source: TerminalView, content: Data) {}
    func clipboardRead(source: TerminalView) -> Data? { nil }
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) { target?.rangeChanged(source: source, startY: startY, endY: endY) }
}

struct TerminalSurface: NSViewRepresentable {
    @ObservedObject var session: TerminalSession
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let terminal = session.terminal!
        terminal.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor), terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminal.topAnchor.constraint(equalTo: container.topAnchor), terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        DispatchQueue.main.async { terminal.window?.makeFirstResponder(terminal) }
        return container
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
