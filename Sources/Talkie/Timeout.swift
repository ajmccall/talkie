import Foundation

/// Runs `body`, cancelling it and throwing `TalkieError.timeout` if it takes
/// longer than `seconds`.
func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    _ body: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TalkieError.timeout("Timed out after \(Int(seconds))s")
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw TalkieError.timeout("Timed out after \(Int(seconds))s")
        }
        return result
    }
}
