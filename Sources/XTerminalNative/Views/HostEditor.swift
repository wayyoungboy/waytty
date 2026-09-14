import SwiftUI
import AppKit
import TerminalCore

struct HostEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var host: Host
    @State private var tab = "基本信息"
    @State private var validation: String?
    let tabs = [("基本信息", "link"), ("连接设置", "slider.horizontal.3"), ("跳板机", "point.3.connected.trianglepath.dotted"), ("其他设置", "text.alignleft")]
    var editing: Bool { store.document.hosts.contains { $0.id == host.id } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "network").foregroundStyle(Theme.accent)
                Text(editing ? "编辑 SSH 连接" : "新建 SSH 连接").font(.system(size: 13, weight: .semibold))
                Spacer(); IconButton(symbol: "xmark", help: "关闭") { dismiss() }
            }.padding(.horizontal, 18).frame(height: 49).background(Theme.panel)
            Divider().overlay(Theme.line)
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 5) {
                    ForEach(tabs, id: \.0) { item in
                        Button { tab = item.0 } label: {
                            HStack(spacing: 9) { Image(systemName: item.1).frame(width: 15); Text(item.0); Spacer() }
                                .foregroundStyle(tab == item.0 ? Theme.accent : Color.secondary)
                                .padding(.horizontal, 12).frame(height: 37)
                                .background(tab == item.0 ? Theme.accent.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    Label("SSH 2", systemImage: "lock.shield").font(.system(size: 10)).foregroundStyle(Theme.muted).padding(10)
                }.padding(12).frame(width: 158)
                Rectangle().fill(Theme.line).frame(width: 1)
                ScrollView {
                    VStack(spacing: 14) {
                        if tab == "基本信息" {
                            editorGroup {
                                editorRow("名称") { TextField("我的服务器", text: $host.name) }
                                editorRow("分组") {
                                    Picker("分组", selection: $host.group) {
                                        ForEach(Array(Set(store.groups + [host.group, "未分组"])).sorted(), id: \.self) { Text($0).tag($0) }
                                    }.labelsHidden()
                                }
                                editorRow("地址", caption: "服务器的 IP 或域名") {
                                    HStack { TextField("server.example.com", text: $host.address); TextField("22", value: $host.port, formatter: NumberFormatter.port).frame(width: 63) }
                                }
                            }
                            editorGroup {
                                editorRow("登录用户") { TextField("root", text: $host.username) }
                                editorRow("验证方式") { Text(host.identityFile.isEmpty ? "系统密钥 / SSH Agent / 交互认证" : "指定私钥").font(.system(size: 11)).foregroundStyle(.secondary) }
                                editorRow("私钥文件", caption: "可选，留空使用默认密钥") {
                                    HStack {
                                        TextField("~/.ssh/id_ed25519", text: $host.identityFile)
                                        Button("选择…", action: chooseKey).buttonStyle(ActionButtonStyle())
                                    }
                                }
                            }
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "info.circle").foregroundStyle(Theme.accent)
                                Text("连接后在终端输入密码或密钥口令。首次连接时会显示服务器指纹供你确认。").foregroundStyle(.secondary).lineSpacing(4)
                            }.font(.system(size: 11)).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        } else if tab == "连接设置" {
                            editorGroup {
                                editorRow("连接超时", caption: "1–300 秒") { TextField("15", value: $host.timeout, formatter: NumberFormatter.port) }
                                editorRow("心跳间隔", caption: "秒，0 表示关闭") { TextField("30", value: $host.keepAlive, formatter: NumberFormatter.port) }
                            }
                            editorGroup {
                                editorRow("终端类型") { Text("xterm-256color").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary) }
                                editorRow("字符编码") { Text("UTF-8").foregroundStyle(.secondary) }
                            }
                        } else if tab == "跳板机" {
                            editorGroup {
                                VStack(alignment: .leading, spacing: 12) {
                                    Label("跳板机链路", systemImage: "point.3.connected.trianglepath.dotted").font(.system(size: 13, weight: .medium))
                                    Text("按实际连接顺序填写，第一项会最先连接。").foregroundStyle(.secondary)
                                    TextField("user@bastion.example.com:22", text: $host.jumpHost).textFieldStyle(.roundedBorder)
                                    Text("多级跳板使用逗号分隔：user@jump1:22,user@jump2:22").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
                                }.padding(16)
                            }
                        } else {
                            editorGroup {
                                editorRow("系统标识", caption: "用于连接列表展示") {
                                    Picker("系统", selection: $host.system) { ForEach(["Linux", "Ubuntu", "Debian", "macOS", "其他"], id: \.self) { Text($0).tag($0) } }.labelsHidden()
                                }
                                editorRow("收藏") { Toggle("加入收藏", isOn: $host.favorite).toggleStyle(.switch).controlSize(.small) }
                            }
                            editorGroup {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("主机备注").fontWeight(.medium)
                                    TextEditor(text: $host.notes).font(.system(size: 12)).scrollContentBackground(.hidden).frame(height: 155)
                                }.padding(16)
                            }
                        }
                    }.padding(20)
                }
            }
            Divider()
            if let validation { Text(validation).font(.system(size: 11)).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 10) }
            HStack {
                Button("保存并连接") { commit(connect: true) }.buttonStyle(ActionButtonStyle())
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(ActionButtonStyle()).keyboardShortcut(.cancelAction)
                Button(editing ? "保存" : "创建") { commit(connect: false) }.buttonStyle(ActionButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
            }.padding(16)
        }.font(.system(size: 12)).frame(width: 770, height: 580).background(Theme.elevated).preferredColorScheme(.dark)
    }
    private func chooseKey() {
        let panel = NSOpenPanel(); panel.title = "选择 SSH 私钥"; panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        if panel.runModal() == .OK, let url = panel.url { host.identityFile = url.path }
    }
    private func commit(connect: Bool) {
        do {
            let valid = try host.validated(); try store.saveHost(valid)
            dismiss(); if connect { store.connect(valid) }
        } catch { validation = error.localizedDescription }
    }
}

func editorGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 0, content: content).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.line))
}

func editorRow<Content: View>(_ title: String, caption: String? = nil, @ViewBuilder content: () -> Content) -> some View {
    HStack(spacing: 14) {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .medium))
            if let caption { Text(caption).font(.system(size: 10)).foregroundStyle(Theme.muted) }
        }.frame(width: 125, alignment: .leading)
        content().textFieldStyle(.roundedBorder).frame(maxWidth: .infinity, alignment: .trailing)
    }.padding(15)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line.opacity(0.55)).frame(height: 1).padding(.horizontal, 15) }
}

extension NumberFormatter {
    static var port: NumberFormatter { let f = NumberFormatter(); f.numberStyle = .none; f.allowsFloats = false; f.usesGroupingSeparator = false; return f }
}
