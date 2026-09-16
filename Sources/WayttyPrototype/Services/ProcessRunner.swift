import Foundation

struct CommandResult: Sendable {
    let status: Int32
    let output: String
}

enum ProcessRunner {
    /// Drain output on a worker queue before waiting, so large listings cannot fill a pipe.
    static func run(_ executable: String, _ arguments: [String], input: String? = nil, timeout: TimeInterval = 30) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                var environment = ProcessInfo.processInfo.environment
                environment["LC_ALL"] = "en_US.UTF-8"
                process.environment = environment
                let output = Pipe(); let stdin = Pipe()
                process.standardOutput = output; process.standardError = output
                process.standardInput = stdin
                do {
                    try process.run()
                    let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                    if let input { try stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8)) }
                    try? stdin.fileHandleForWriting.close()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit(); deadline.cancel()
                    continuation.resume(returning: CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self)))
                } catch {
                    if process.isRunning { process.terminate() }
                    try? stdin.fileHandleForWriting.close()
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
