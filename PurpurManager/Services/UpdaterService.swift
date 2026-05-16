import Foundation

/// Sparkle-ready seam. Add Sparkle as an optional package later and implement this protocol in one place.
protocol UpdateChecking: Sendable {
    func checkForUpdates() async
}

struct NoopUpdaterService: UpdateChecking {
    func checkForUpdates() async {}
}
