import Foundation

public struct SSHImportResult {
    public var hosts: [Host]
    public var warnings: [String]
}

public enum SSHConfigImporter {
    /// Import explicit Host blocks only; never execute Include, Match exec, or ProxyCommand.
    public static func parse(_ text: String) -> SSHImportResult {
        var hosts: [Host] = []
        var warnings = Set<String>()
        var aliases: [String] = []
        var values: [String: String] = [:]
        func flush() {
            for alias in aliases {
                var host = Host()
                host.name = alias; host.address = values["hostname"] ?? alias
                host.username = values["user"] ?? NSUserName()
                host.port = Int(values["port"] ?? "22") ?? 0
                host.identityFile = values["identityfile"] ?? ""
                host.jumpHost = values["proxyjump"] ?? ""
                if host.jumpHost == "none" { host.jumpHost = "" }
                host.group = "SSH Config"
                if let valid = try? host.validated() { hosts.append(valid) }
                else { warnings.insert("跳过无效条目：\(alias)") }
            }
        }
        for rawLine in text.components(separatedBy: .newlines) {
            let tokens = tokenize(rawLine)
            guard let key = tokens.first?.lowercased(), tokens.count > 1 else { continue }
            let value = tokens.dropFirst().joined(separator: " ")
            switch key {
            case "host":
                flush(); values = [:]
                aliases = tokens.dropFirst().filter { !$0.contains(where: { "*?!".contains($0) }) }
                if aliases.count != tokens.count - 1 { warnings.insert("通配符 Host 规则未展开。") }
            case "match": flush(); aliases = []; values = [:]; warnings.insert("Match 条件未执行。")
            case "include": warnings.insert("Include 文件未自动读取；请分别导入。")
            case "hostname", "user", "port", "identityfile", "proxyjump":
                if values[key] == nil { values[key] = value }
            default: warnings.insert("未导入高级选项：\(key)")
            }
        }
        flush()
        return SSHImportResult(hosts: hosts, warnings: warnings.sorted())
    }

    private static func tokenize(_ line: String) -> [String] {
        var result: [String] = []; var token = ""; var quote: Character?; var escaped = false
        for c in line {
            if escaped { token.append(c); escaped = false; continue }
            if c == "\\" { escaped = true; continue }
            if let q = quote { if c == q { quote = nil } else { token.append(c) }; continue }
            if c == "#" { break }
            if c == "\"" || c == "'" { quote = c; continue }
            if c.isWhitespace || (c == "=" && result.count <= 1) {
                if !token.isEmpty { result.append(token); token = "" }
            } else { token.append(c) }
        }
        if !token.isEmpty { result.append(token) }
        return result
    }
}
