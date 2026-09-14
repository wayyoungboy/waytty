"""Loopback-only SSH/SFTP integration fixture; never executes shell commands."""
import asyncio
import json
import sys

import asyncssh


class FixtureServer(asyncssh.SSHServer):
    def begin_auth(self, username):
        return True

    def password_auth_supported(self):
        return True

    def validate_password(self, username, password):
        return username == "fixture" and password == "fixture-only-password"

    def connection_requested(self, dest_host, dest_port, orig_host, orig_port):
        return dest_host == "127.0.0.1"


async def session(process):
    if process.command:
        if process.command == "xtn-utf8-check":
            process.stdout.write("中文 SSH ✓\n")
            process.stderr.write("诊断信息\n")
            process.exit(7)
        elif process.command == "xtn-large-output":
            process.stdout.write("x" * (2 * 1024 * 1024))
            process.exit(0)
        elif process.command == "xtn-wait":
            await process.stdin.read()
            process.exit(0)
        else:
            process.stderr.write("Fixture accepts only xtn-utf8-check\n")
            process.exit(127)
        return
    process.stdout.write("XTerminal Native · SSH 测试服务\r\nfixture$ ")
    async for line in process.stdin:
        if line.strip() == "exit":
            break
        process.stdout.write("收到: " + line.rstrip() + "\r\nfixture$ ")
    process.exit(0)


async def main():
    root = sys.argv[1]
    key = asyncssh.generate_private_key("ssh-ed25519")
    server = await asyncssh.create_server(
        FixtureServer, "127.0.0.1", 0, server_host_keys=[key],
        process_factory=session,
        sftp_factory=lambda channel: asyncssh.SFTPServer(channel, chroot=root),
    )
    print(json.dumps({"port": server.get_port()}), flush=True)
    await asyncio.to_thread(sys.stdin.readline)
    server.close()
    await server.wait_closed()


if __name__ == "__main__":
    asyncio.run(main())
