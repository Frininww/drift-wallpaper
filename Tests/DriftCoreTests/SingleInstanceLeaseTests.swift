import XCTest
@testable import DriftCore

final class SingleInstanceLeaseTests: XCTestCase {
    func testOnlyOneOwnerCanHoldTheSameLease() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("instance.lock")
        let owner = try XCTUnwrap(SingleInstanceLease.acquire(at: url))
        try withExtendedLifetime(owner) {
            XCTAssertNil(try SingleInstanceLease.acquire(at: url))
        }
    }

    func testClosingOwnerReleasesLeaseWithoutDeletingTheFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("instance.lock")
        var owner = try SingleInstanceLease.acquire(at: url)
        XCTAssertNotNil(owner)
        owner = nil
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let replacement = try XCTUnwrap(SingleInstanceLease.acquire(at: url))
        try withExtendedLifetime(replacement) {
            XCTAssertNil(try SingleInstanceLease.acquire(at: url))
        }
    }
}
