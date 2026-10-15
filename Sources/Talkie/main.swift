import AppKit

let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--selftest"), index + 1 < arguments.count {
    let path = arguments[index + 1]
    let vocabularyPath = arguments.firstIndex(of: "--vocab").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
    // Keep the main queue serviced: model loading hops to the main actor,
    // so blocking the main thread here would deadlock.
    Task.detached {
        exit(await SelfTest.run(path: path, vocabularyPath: vocabularyPath))
    }
    dispatchMain()
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
