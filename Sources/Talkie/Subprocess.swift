import Darwin
import Foundation

/// Runs one child process with stdin supplied and both output pipes drained off
/// the calling thread. Cancelling the task (including via `withTimeout`)
/// terminates the child, then kills it if it lingers.
enum Subprocess {
    struct Output: Sendable {
        let status: Int32
        let stdout: Data
        let stderr: Data

        var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
        var stderrText: String { String(decoding: stderr, as: UTF8.self) }
        /// Last non-empty stderr line, for log messages.
        var stderrTail: String {
            let lines = stderrText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            return lines.last { !$0.isEmpty }.map { String($0.prefix(200)) } ?? ""
        }
    }

    static func run(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        directory: URL? = nil,
        input: Data = Data()
    ) async throws -> Output {
        let session = Session(executable: executable, arguments: arguments, environment: environment,
                              directory: directory, input: input)
        return try await session.run()
    }
}

private final class Session: @unchecked Sendable {
    private let executable: URL
    private let arguments: [String]
    private let environment: [String: String]
    private let directory: URL?
    private let input: Data
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false

    init(executable: URL, arguments: [String], environment: [String: String], directory: URL?, input: Data) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.directory = directory
        self.input = input
    }

    func run() async throws -> Subprocess.Output {
        try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { self.execute(continuation) }
            }
        }, onCancel: { stop() })
    }

    private func stop() {
        lock.lock()
        stopped = true
        let child = process
        lock.unlock()
        guard let child else { return }
        if child.isRunning { child.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }

    private func execute(_ continuation: CheckedContinuation<Subprocess.Output, Error>) {
        let child = Process()
        child.executableURL = executable
        child.arguments = arguments
        child.environment = environment
        child.currentDirectoryURL = directory
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = stderr

        lock.lock()
        if stopped {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        do {
            try child.run()
            process = child
            lock.unlock()
        } catch {
            lock.unlock()
            continuation.resume(throwing: TalkieError.launchFailed("could not launch \(executable.lastPathComponent): \(error.localizedDescription)"))
            return
        }

        let out = DataBox(), err = DataBox(), group = DispatchGroup()
        group.enter(); DispatchQueue.global().async { out.read(stdout.fileHandleForReading); group.leave() }
        group.enter(); DispatchQueue.global().async { err.read(stderr.fileHandleForReading); group.leave() }
        // Process closes its own copies; close the parent's unused ends for reliable EOF.
        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()
        try? stdin.fileHandleForReading.close()
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try? stdin.fileHandleForWriting.write(contentsOf: input)
        try? stdin.fileHandleForWriting.close()
        child.waitUntilExit()
        group.wait()

        lock.lock()
        process = nil
        let cancelled = stopped
        lock.unlock()
        if cancelled {
            continuation.resume(throwing: CancellationError())
        } else {
            continuation.resume(returning: .init(status: child.terminationStatus, stdout: out.data, stderr: err.data))
        }
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = Data()
    var data: Data { lock.lock(); defer { lock.unlock() }; return stored }

    /// Drains to EOF even past the cap so a chatty child can never block on a full pipe.
    func read(_ handle: FileHandle) {
        defer { try? handle.close() }
        while let chunk = try? handle.read(upToCount: 8192), !chunk.isEmpty {
            lock.lock()
            stored.append(chunk.prefix(max(0, 2_000_000 - stored.count)))
            lock.unlock()
        }
    }
}
