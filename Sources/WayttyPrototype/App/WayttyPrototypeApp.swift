import SwiftUI
import AppKit

@main
struct WayttyPrototypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        Window("waytty", id: "main") {
            ContentView().environmentObject(store).preferredColorScheme(.dark)
                .onAppear { delegate.store = store }
        }
        .defaultSize(width: 1280, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建 SSH 连接") { store.newHost() }.keyboardShortcut("n")
                Button("新建本地终端") { store.newLocalTerminal() }.keyboardShortcut("t")
                Button("关闭当前会话") { if let session = store.activeSession { store.closeSession(session) } }
                    .keyboardShortcut("w").disabled(store.activeSession == nil || store.page != .terminal)
            }
            CommandMenu("连接") {
                Button("连接管理") { store.page = .connections }.keyboardShortcut("1")
                Button("控制台") { if store.sessions.isEmpty { store.newLocalTerminal() }; store.page = .terminal }.keyboardShortcut("2")
                Divider()
                Button("分屏终端") { store.splitTerminal() }.keyboardShortcut("d").disabled(store.activeSession == nil)
                Button("显示文件管理") { store.showFiles.toggle(); store.page = .terminal }.keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                Button("导入 SSH Config…", action: store.importSSHConfig)
                Button("导入仓库…", action: store.importWorkspace)
                Button("导出仓库…", action: store.exportWorkspace)
            }
        }
        Settings { SettingsView().environmentObject(store).preferredColorScheme(.dark) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: AppStore?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.sessions.contains(where: { $0.state != .ended }) else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = "退出并关闭所有会话？"; alert.informativeText = "正在运行的终端、SSH 连接和隧道将被关闭。"
        alert.addButton(withTitle: "退出"); alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) { store?.stopAll() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
