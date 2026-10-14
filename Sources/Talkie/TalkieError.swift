import Foundation

enum TalkieError: LocalizedError, Equatable {
    case audio(String)
    case notReady(String)
    case permission(String)
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .audio(let m), .notReady(let m), .permission(let m), .timeout(let m): return m
        }
    }
}
