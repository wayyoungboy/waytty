import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("terminalFontSize") var fontSize = 13.0
    @AppStorage("shellPath") var shell = "/bin/zsh"
    var body: some View {
        TabView {
            Form {
                Section("本地终端") {
                    Picker("默认 Shell", selection: $shell) { Text("zsh").tag("/bin/zsh"); Text("bash").tag("/bin/bash") }
                    Slider(value: $fontSize, in: 10...24, step: 1) { Text("字体大小 · \(Int(fontSize)) pt") }
                    Text("新设置应用于新建的终端会话。").font(.caption).foregroundStyle(.secondary)
                }
                Section("快捷键") {
                    LabeledContent("新建 SSH 连接", value: "⌘N")
                    LabeledContent("本地终端", value: "⌘T")
                    LabeledContent("分屏", value: "⌘D")
                    LabeledContent("文件管理", value: "⇧⌘E")
                    LabeledContent("切换连接 / 控制台", value: "⌘1 / ⌘2")
                }
            }.formStyle(.grouped).tabItem { Label("终端", systemImage: "terminal") }
            Form {
                Section("连接仓库") {
                    Text(store.storageURL.path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                    HStack { Button("导入 SSH Config…", action: store.importSSHConfig); Button("导出备份…", action: store.exportWorkspace) }
                    Text("仓库保存在本机，含主机、密钥路径、隧道、笔记和命令。密码在终端交互输入，不保存到仓库。").font(.caption).foregroundStyle(.secondary)
                }
                Section("关于") {
                    LabeledContent("waytty", value: "0.1.0")
                    LabeledContent("界面", value: "SwiftUI + AppKit")
                    LabeledContent("终端", value: "SwiftTerm 1.20.0 · MIT")
                    LabeledContent("连接", value: "系统 OpenSSH / SFTP")
                }
            }.formStyle(.grouped).tabItem { Label("仓库与关于", systemImage: "internaldrive") }
        }.padding(12).frame(width: 580, height: 430)
    }
}
