import Foundation

public struct Host: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var name = ""
    public var address = ""
    public var port = 22
    public var username = "root"
    public var group = "未分组"
    public var favorite = false
    public var system = "Linux"
    public var notes = ""
    public var identityFile = ""
    public var jumpHost = ""
    public var timeout = 15
    public var keepAlive = 30
    public var lastConnected: Date?

    public init() {}
    public var endpoint: String { "\(username)@\(address):\(port)" }

    public func validated() throws -> Host {
        var host = self
        host.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        host.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        host.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        host.group = group.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.group.isEmpty { host.group = "未分组" }
        guard !host.name.isEmpty else { throw InputError.invalid("请填写连接名称。") }
        guard Self.validAddress(host.address) else { throw InputError.invalid("地址应为 IP 或域名，不包含协议、空格或端口。") }
        guard host.username.range(of: "^[A-Za-z0-9_][A-Za-z0-9_.-]*$", options: .regularExpression) != nil else {
            throw InputError.invalid("请填写有效的登录用户。")
        }
        guard (1...65535).contains(port) else { throw InputError.invalid("端口范围为 1–65535。") }
        guard (1...300).contains(timeout), (0...3600).contains(keepAlive) else {
            throw InputError.invalid("超时时间应为 1–300 秒，心跳应为 0–3600 秒。")
        }
        guard !identityFile.contains(where: { $0.isNewline || $0 == "\0" }) else { throw InputError.invalid("密钥路径无效。") }
        if !jumpHost.isEmpty {
            for jump in jumpHost.split(separator: ",", omittingEmptySubsequences: false) {
                guard String(jump).range(of: "^(?:[A-Za-z0-9_][A-Za-z0-9_.-]*@)?(?:[A-Za-z0-9_][A-Za-z0-9_.-]*|\\[[a-fA-F0-9:]+\\])(?::[0-9]{1,5})?$", options: .regularExpression) != nil else {
                    throw InputError.invalid("跳板机格式为 user@host:port，多级跳板用逗号分隔。")
                }
            }
        }
        return host
    }

    public static func validAddress(_ value: String) -> Bool {
        !value.isEmpty && value.range(of: "^[A-Za-z0-9_][A-Za-z0-9_.:-]*$", options: .regularExpression) != nil
    }
}

public enum InputError: LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

public enum ForwardKind: String, Codable, CaseIterable, Sendable {
    case local = "本地转发", remote = "远程转发", dynamic = "SOCKS5 代理"
    public var option: String { switch self { case .local: return "-L"; case .remote: return "-R"; case .dynamic: return "-D" } }
}

public struct Tunnel: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var name = ""
    public var hostID: UUID?
    public var kind: ForwardKind = .local
    public var bindPort = 8080
    public var destination = "127.0.0.1"
    public var destinationPort = 80
    public init() {}
    public var specification: String {
        kind == .dynamic ? "127.0.0.1:\(bindPort)" : "127.0.0.1:\(bindPort):\(destination.contains(":") ? "[\(destination)]" : destination):\(destinationPort)"
    }
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, hostID != nil else { throw InputError.invalid("请填写名称并选择 SSH 连接。") }
        guard (1...65535).contains(bindPort), (1...65535).contains(destinationPort), Host.validAddress(destination) else {
            throw InputError.invalid("请检查转发地址与端口。")
        }
    }
}

public enum SSHCommand {
    public static func arguments(for host: Host, socket: String? = nil, tunnel: Tunnel? = nil) throws -> [String] {
        let h = try host.validated()
        var args = ["-F", "/dev/null", "-p", String(h.port), "-l", h.username,
                    "-o", "ConnectTimeout=\(h.timeout)", "-o", "ServerAliveInterval=\(h.keepAlive)",
                    "-o", "ServerAliveCountMax=3", "-o", "StrictHostKeyChecking=ask",
                    "-o", "ForwardAgent=no", "-o", "ForwardX11=no"]
        if !h.identityFile.isEmpty { args += ["-i", (h.identityFile as NSString).expandingTildeInPath, "-o", "IdentitiesOnly=yes"] }
        if !h.jumpHost.isEmpty { args += ["-J", h.jumpHost] }
        if let socket { args += ["-M", "-S", socket, "-o", "ControlPersist=no"] }
        if let tunnel {
            try tunnel.validate()
            args += ["-N", "-T", "-o", "ExitOnForwardFailure=yes", tunnel.kind.option, tunnel.specification]
        } else { args += ["-tt"] }
        return args + [h.address]
    }

    /// Reuse only an authenticated master. If it has gone away, never open a second transport.
    public static func multiplexArguments(for host: Host, socket: String) -> [String] {
        ["-F", "/dev/null", "-o", "ControlPath=\(socket)", "-o", "ControlMaster=no",
         "-o", "ProxyCommand=/usr/bin/false", "-o", "BatchMode=yes", "-o", "ConnectTimeout=3",
         "-p", String(host.port), "-l", host.username, host.address]
    }

    public static func display(_ args: [String]) -> String { (["ssh"] + args).map(shellQuote).joined(separator: " ") }
    public static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
