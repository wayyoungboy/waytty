import XCTest
@testable import TerminalCore

typealias Host = TerminalCore.Host

final class TerminalCoreTests: XCTestCase {
    func host() -> Host { var host = Host(); host.name = "Test"; host.address = "example.com"; return host }

    func testSSHArgumentsPreventOptionInjection() throws {
        for value in ["-oProxyCommand=whoami", "host;id", "host\nwhoami", "user@host", "https://example.com", "$(id)"] {
            var host = host(); host.address = value
            XCTAssertThrowsError(try SSHCommand.arguments(for: host))
        }
        var h = host(); h.username = "root -oProxyCommand=id"
        XCTAssertThrowsError(try h.validated())
        h = host(); h.jumpHost = "root@host -oProxyCommand=id"
        XCTAssertThrowsError(try h.validated())
    }

    func testSSHArgumentsKeepKeysAndJumpsAsSeparateArguments() throws {
        var h = host(); h.port = 2222; h.identityFile = "/tmp/key with spaces"; h.jumpHost = "jump@bastion:22,root@inner:2200"
        let args = try SSHCommand.arguments(for: h, socket: "/tmp/private/socket")
        XCTAssertEqual(args.last, "example.com")
        XCTAssertTrue(args.contains("StrictHostKeyChecking=ask"))
        XCTAssertTrue(args.contains("/tmp/key with spaces"))
        XCTAssertTrue(args.contains(h.jumpHost))
        XCTAssertTrue(args.contains("-tt"))
        XCTAssertFalse(args.contains("StrictHostKeyChecking=no"))
    }

    func testIPv6AndPortValidation() throws {
        var h = host(); h.address = "2001:db8::1"; h.port = 65535
        XCTAssertNoThrow(try h.validated())
        h.port = 65536; XCTAssertThrowsError(try h.validated())
        h.port = 0; XCTAssertThrowsError(try h.validated())
    }

    func testTunnelIsBoundToLoopbackAndDoesNotOpenShell() throws {
        let h = host(); var tunnel = Tunnel(); tunnel.hostID = h.id; tunnel.name = "db"; tunnel.bindPort = 15432; tunnel.destinationPort = 5432
        let args = try SSHCommand.arguments(for: h, tunnel: tunnel)
        XCTAssertTrue(args.contains("-N")); XCTAssertTrue(args.contains("ExitOnForwardFailure=yes"))
        XCTAssertTrue(args.contains("127.0.0.1:15432:127.0.0.1:5432"))
        XCTAssertFalse(args.contains("-tt"))
        tunnel.kind = .dynamic
        XCTAssertEqual(tunnel.specification, "127.0.0.1:15432")
    }

    func testMultiplexCannotFallBackToNewConnection() {
        let args = SSHCommand.multiplexArguments(for: host(), socket: "/tmp/sock")
        XCTAssertTrue(args.contains("ProxyCommand=/usr/bin/false"))
        XCTAssertTrue(args.contains("BatchMode=yes"))
    }

    func testSFTPPathQuoting() throws {
        XCTAssertEqual(try SFTP.quote("/home/user/my file.txt"), "\"/home/user/my file.txt\"")
        XCTAssertEqual(try SFTP.quote("a*b?[c]\""), "\"a*b?[c]\\\"\"")
        XCTAssertThrowsError(try SFTP.quote("foo\nrm /important"))
        XCTAssertThrowsError(try SFTP.quote("foo\0bar"))
    }

    func testSFTPListingPreservesSpacesAndSortsDirectoriesFirst() {
        let output = """
        sftp> ls -la
        drwxr-xr-x    2 root root      4096 Sep 12 12:30 .
        drwxr-xr-x    2 root root      4096 Sep 12 12:30 ..
        -rw-r--r--    1 root root       123 Sep 12 12:30 hello world.txt
        drwxr-xr-x    2 root root      4096 Sep 12 12:30 my folder
        lrwxrwxrwx    1 root root        10 Sep 12 12:30 link -> target
        """
        let files = SFTP.parseListing(output)
        XCTAssertEqual(files.map(\.name), ["my folder", "hello world.txt", "link"])
        XCTAssertEqual(files[1].size, 123)
        XCTAssertTrue(files[2].isLink)
    }

    func testSSHImportHandlesQuotesAndDoesNotExecuteDirectives() {
        let text = """
        Include ~/.ssh/other
        Host dev staging
          HostName example.com
          User deploy
          Port 2222
          IdentityFile "/tmp/key with spaces"
          ProxyJump root@bastion:22
          ProxyCommand touch /tmp/never
        Host *
          ServerAliveInterval 30
        Match exec "touch /tmp/never"
          HostName not-imported
        Host prod
          HostName prod.example.com
        """
        let result = SSHConfigImporter.parse(text)
        XCTAssertEqual(result.hosts.map(\.name), ["dev", "staging", "prod"])
        XCTAssertEqual(result.hosts[0].identityFile, "/tmp/key with spaces")
        XCTAssertEqual(result.hosts[0].port, 2222)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testWorkspaceRoundTripAndDuplicateRejection() throws {
        var document = WorkspaceDocument(); document.hosts = [host()]; document.notes = [Note(title: "中文", body: "hello")]
        let data = try JSONEncoder().encode(document)
        XCTAssertEqual(try JSONDecoder().decode(WorkspaceDocument.self, from: data), document)
        document.hosts.append(document.hosts[0])
        XCTAssertThrowsError(try document.validate())
    }

    func testSSHConfigEqualsAndInvalidPort() {
        let imported = SSHConfigImporter.parse("Host dev\nHostName = dev.example.com\nUser=deploy\nPort=2200\nHost invalid\nPort nope")
        XCTAssertEqual(imported.hosts.count, 1)
        XCTAssertEqual(imported.hosts.first?.address, "dev.example.com")
        XCTAssertEqual(imported.hosts.first?.username, "deploy")
        XCTAssertEqual(imported.hosts.first?.port, 2200)
    }
}
