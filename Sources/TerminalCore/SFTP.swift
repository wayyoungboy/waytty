import Foundation

public struct RemoteFile: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let permissions: String
    public let size: Int64
    public let modified: String
    public var isDirectory: Bool { permissions.hasPrefix("d") }
    public var isLink: Bool { permissions.hasPrefix("l") }
}

public enum SFTP {
    /// OpenSSH makeargv automatically escapes glob metacharacters inside double quotes.
    public static func quote(_ value: String) throws -> String {
        guard !value.contains(where: { $0.isNewline || $0 == "\0" }) else { throw InputError.invalid("SFTP 不支持此路径中的换行符。") }
        var result = "\""
        for c in value {
            if "\\\"".contains(c) { result.append("\\") }
            result.append(c)
        }
        return result + "\""
    }

    public static func joined(_ directory: String, _ name: String) -> String {
        (directory == "/" ? "/" : directory + "/") + name
    }

    public static func parseListing(_ output: String) -> [RemoteFile] {
        let pattern = #"^([bcdlps-][rwxStTs-]{9}[+@.]?)\s+(?:\d+|\?)\s+\S+\s+\S+\s+(\d+)\s+(\S+\s+\d+\s+\S+)\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return output.components(separatedBy: .newlines).compactMap { line in
            let ns = line as NSString
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
            let permissions = ns.substring(with: match.range(at: 1))
            var name = ns.substring(with: match.range(at: 4))
            if permissions.hasPrefix("l"), let r = name.range(of: " -> ") { name = String(name[..<r.lowerBound]) }
            guard name != ".", name != ".." else { return nil }
            return RemoteFile(name: name, permissions: permissions, size: Int64(ns.substring(with: match.range(at: 2))) ?? 0,
                              modified: ns.substring(with: match.range(at: 3)))
        }.sorted { a, b in a.isDirectory != b.isDirectory ? a.isDirectory : a.name.localizedStandardCompare(b.name) == .orderedAscending }
    }
}
