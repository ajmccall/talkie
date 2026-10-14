import Foundation

enum TalkieError: LocalizedError, Equatable {
    case audio(String)
    case notReady(String)
    case permission(String)
    case timeout(String)
    case launchFailed(String)
    case skill(String)

    var errorDescription: String? {
        switch self {
        case .audio(let m), .notReady(let m), .permission(let m), .timeout(let m), .launchFailed(let m), .skill(let m): return m
        }
    }
}
