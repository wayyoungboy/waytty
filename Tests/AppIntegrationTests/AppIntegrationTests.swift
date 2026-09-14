import XCTest
import Foundation
import TerminalCore
@testable import XTerminalNative

final class AppIntegrationTests: XCTestCase {
    @MainActor
    func testPersistenceRestoresGroupsNotesAndFavorites() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("xtn-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("workspace.json")
        let store = AppStore(storageURL: url)
        defer { store.stopAll() }
        var host = TerminalCore.Host(); host.name = "测试服务器"; host.address = "localhost"; host.favorite = true; host.group = "测试环境"
        try store.saveHost(host)
        store.document.notes.append(Note(title: "部署", body: "测试笔记")); store.save()
        let reloaded = AppStore(storageURL: url)
        defer { reloaded.stopAll() }
        XCTAssertEqual(reloaded.document.hosts, [host])
        XCTAssertEqual(reloaded.document.notes.first?.body, "测试笔记")
        reloaded.filter = .favorites; XCTAssertEqual(reloaded.visibleHosts.count, 1)
        reloaded.search = "localhost"; XCTAssertEqual(reloaded.visibleHosts.count, 1)
        reloaded.search = "missing"; XCTAssertEqual(reloaded.visibleHosts.count, 0)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    @MainActor
    func testCorruptRepositoryIsNeverOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("xtn-corrupt-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("workspace.json")
        let original = Data("{broken".utf8); try original.write(to: url)
        let store = AppStore(storageURL: url); defer { store.stopAll() }
        XCTAssertNotNil(store.error)
        store.save()
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testProcessRunnerDrainsOutputBeyondPipeCapacity() async throws {
        let result = try await ProcessRunner.run("/usr/bin/awk", ["BEGIN { for (i=0; i<20000; i++) print \"abcdefghij\" }"], timeout: 10)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output.count, 220000)
    }

    func testRealSFTPLiteralFilenamesAndTransfers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("xtn-sftp-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("source [1]*? 中文.txt")
        let destination = root.appendingPathComponent("download [2]*?.txt")
        let payload = Data("Hello SFTP, 中文。\n".utf8)
        try payload.write(to: original)
        let commands = [
            "cd \(try SFTP.quote(root.path))", "pwd", "ls -la",
            "get \(try SFTP.quote(original.path)) \(try SFTP.quote(destination.path))"
        ].joined(separator: "\n") + "\n"
        let result = try await ProcessRunner.run("/usr/bin/sftp", ["-D", "/usr/libexec/sftp-server", "-b", "-"], input: commands)
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(SFTP.parseListing(result.output).contains { $0.name == original.lastPathComponent }, result.output)
        XCTAssertEqual(try Data(contentsOf: destination), payload)
    }
}
