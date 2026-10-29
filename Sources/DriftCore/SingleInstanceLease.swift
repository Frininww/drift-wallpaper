import Foundation
import Darwin

/// Kernel-owned lock shared by installed, downloaded and development copies.
/// Closing the descriptor (including on a crash) releases ownership. Never
/// unlink a lock file: doing so can create two independent lock inodes.
public final class SingleInstanceLease {
    private let descriptor: Int32
    private init(descriptor: Int32) { self.descriptor = descriptor }

    public static func acquire(at url: URL) throws -> SingleInstanceLease? {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            if code == EWOULDBLOCK || code == EAGAIN { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return SingleInstanceLease(descriptor: descriptor)
    }

    deinit { close(descriptor) }
}
