import AppKit
import DriftCore

@MainActor
final class InstanceCoordinator {
    static let bundleID = "app.drift.wallpaper"
    static var showLibraryNotification: Notification.Name {
        Notification.Name("app.drift.wallpaper.showLibrary.\(getuid())")
    }
    private var lease: SingleInstanceLease?

    func acquire() throws -> Bool {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Drift", isDirectory: true)
        lease = try SingleInstanceLease.acquire(at: directory.appendingPathComponent("instance.lock"))
        return lease != nil
    }

    func activateOwner() {
        DistributedNotificationCenter.default().postNotificationName(Self.showLibraryNotification, object: nil, userInfo: nil, deliverImmediately: true)
        otherCopies.first?.activate(options: [.activateIgnoringOtherApps])
    }

    /// Old releases did not take a lease. Retire them before any new desktop
    /// windows are created; only this app's exact bundle identifier is eligible.
    func retireLegacyCopies() async throws {
        let copies = otherCopies
        for copy in copies { copy.terminate() }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while copies.contains(where: { !$0.isTerminated }), ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        for copy in copies where !copy.isTerminated { copy.forceTerminate() }
        let forceDeadline = ProcessInfo.processInfo.systemUptime + 1
        while copies.contains(where: { !$0.isTerminated }), ProcessInfo.processInfo.systemUptime < forceDeadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard copies.allSatisfy(\.isTerminated) else { throw InstanceError.couldNotRetire }
    }

    private var otherCopies: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
    }

    enum InstanceError: LocalizedError {
        case couldNotRetire
        var errorDescription: String? { "An older Drift copy could not be stopped. Quit it before opening this version." }
    }
}
