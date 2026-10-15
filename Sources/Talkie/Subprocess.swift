import Darwin
import Foundation

/// Runs one child process with stdin supplied and both output pipes drained off
/// the calling thread. Cancelling the task (including via `withTimeout`)
/// terminates the child, then kills it if it lingers.
///
/// Two shapes: `run` does everything in one call; `spawn` launches the child
/// with stdin held open so its start-up cost is paid early, and `finish` on
/// the returned handle supplies the input later and collects the output.
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
        let handle = try spawn(executable: executable, arguments: arguments, environment: environment, directory: directory)
        return try await handle.finish(input: input)
    }

    /// Launches the child now. Call `finish` to send stdin and wait, or
    /// `discard` to kill it unused. Throws if the executable cannot start.
    static func spawn(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        directory: URL? = nil
    ) throws -> Handle {
        try Handle(executable: executable, arguments: arguments, environment: environment, directory: directory)
    }

    /// A running child whose stdin is still open.
    final class Handle: @unchecked Sendable {
        let startedAt = Date()
        private let process = Process()
        private let stdin = Pipe()
        private let out = DataBox()
        private let err = DataBox()
        private let drained = DispatchGroup()
        private let lock = NSLock()
        private var stopped = false
        private var finished = false
        private var continuation: CheckedContinuation<Output, Error>?

        fileprivate init(executable: URL, arguments: [String], environment: [String: String], directory: URL?) throws {
            let stdout = Pipe(), stderr = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = environment
            process.currentDirectoryURL = directory
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
            } catch {
                throw TalkieError.launchFailed("could not launch \(executable.lastPathComponent): \(error.localizedDescription)")
            }
            let out = self.out, err = self.err
            drained.enter(); DispatchQueue.global().async { out.read(stdout.fileHandleForReading); self.drained.leave() }
            drained.enter(); DispatchQueue.global().async { err.read(stderr.fileHandleForReading); self.drained.leave() }
            // Process closes its own copies; close the parent's unused ends for reliable EOF.
            try? stdout.fileHandleForWriting.close()
            try? stderr.fileHandleForWriting.close()
            try? stdin.fileHandleForReading.close()
            _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        }

        var isRunning: Bool { process.isRunning }

        /// Writes `input` to the child's stdin, closes it, and waits for exit.
        /// Cancelling the calling task terminates the child.
        ///
        /// `completeWhen` is checked against each stdout line as it arrives; a
        /// match ends the wait, terminates the child, and reports status 0 with
        /// the output so far. For children that keep running after they have
        /// answered (a stream-json session does not exit on stdin EOF).
        func finish(input: Data, completeWhen: (@Sendable (String) -> Bool)? = nil) async throws -> Output {
            guard claimForFinish() else { throw CancellationError() }
            if let completeWhen {
                out.onLine = { [weak self] line in
                    guard let self, completeWhen(line) else { return }
                    self.out.onLine = nil
                    // Do not wait for the drain: a grandchild may hold the pipe open.
                    self.resume(.success(.init(status: 0, stdout: self.out.data, stderr: self.err.data)))
                    self.terminate()
                }
            }
            return try await withTaskCancellationHandler(operation: {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { continuation in
                    lock.lock()
                    self.continuation = continuation
                    lock.unlock()
                    DispatchQueue.global(qos: .userInitiated).async { self.wait(input: input) }
                }
            }, onCancel: { discard() })
        }

        /// Hands the result to whichever of exit, early completion or
        /// cancellation gets there first; the rest are ignored.
        private func resume(_ result: Result<Output, Error>) {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(with: result)
        }

        /// True the first time, so stdin is written exactly once.
        private func claimForFinish() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !finished, !stopped else { return false }
            finished = true
            return true
        }

        /// Terminates the child (SIGTERM, then SIGKILL a second later). Safe to call repeatedly.
        func discard() {
            lock.lock()
            let first = !stopped
            stopped = true
            lock.unlock()
            guard first else { return }
            terminate()
        }

        private func terminate() {
            let child = process
            if child.isRunning { child.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }

        private func wait(input: Data) {
            try? stdin.fileHandleForWriting.write(contentsOf: input)
            try? stdin.fileHandleForWriting.close()
            process.waitUntilExit()
            drained.wait()

            lock.lock()
            let cancelled = stopped
            lock.unlock()
            if cancelled {
                resume(.failure(CancellationError()))
            } else {
                resume(.success(.init(status: process.terminationStatus, stdout: out.data, stderr: err.data)))
            }
        }
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = Data()
    private var scanned = 0
    private var handler: ((String) -> Void)?
    var data: Data { lock.lock(); defer { lock.unlock() }; return stored }

    /// Called with each complete line as it arrives, off the main thread.
    var onLine: ((String) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return handler }
        set { lock.lock(); handler = newValue; lock.unlock() }
    }

    /// Drains to EOF even past the cap so a chatty child can never block on a full pipe.
    /// `availableData` returns each chunk as it arrives (`read(upToCount:)` would
    /// wait for the full count or EOF), which is what line-by-line completion needs.
    func read(_ handle: FileHandle) {
        defer { try? handle.close() }
        while case let chunk = handle.availableData, !chunk.isEmpty {
            lock.lock()
            stored.append(chunk.prefix(max(0, 2_000_000 - stored.count)))
            let handler = self.handler
            var lines: [String] = []
            if handler != nil {
                while let newline = stored[scanned...].firstIndex(of: 0x0A) {
                    lines.append(String(decoding: stored[scanned..<newline], as: UTF8.self))
                    scanned = newline + 1
                }
            }
            lock.unlock()
            for line in lines { handler?(line) }
        }
    }
}
