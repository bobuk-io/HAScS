// Writes that never follow a planted symlink, never leave a half-written file and keep the old
// permissions; a lock that also keeps a second copy of an app from running. From Splash Finish.
import Darwin
import Foundation

public enum SafeFileError: LocalizedError, Equatable {
    case symlink(String)
    case cannotWrite(String)
    case cannotLock(String)
    case locked(String)

    public var errorDescription: String? {
        switch self {
        case .symlink(let path): "Refusing symlink: \(path)"
        case .cannotWrite(let path): "Cannot write \(path)"
        case .cannotLock(let path): "Cannot open lock \(path)"
        case .locked(let message): message
        }
    }
}

public enum SafeFile {
    /// Refuses a symlink at any existing component of `url`, including a dangling one. The macOS
    /// root aliases `/var`, `/tmp` and `/etc` (links into `/private`) are allowed.
    public static func check(_ url: URL) throws {
        var path = url.standardizedFileURL
        while path.path != "/" {
            var info = stat()
            if lstat(path.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK {
                let alias = path.path
                let destination = (try? FileManager.default.destinationOfSymbolicLink(atPath: alias)) ?? ""
                let systemAlias = ["/var", "/tmp", "/etc"].contains(alias)
                    && ["private" + alias, "/private" + alias].contains(destination)
                if !systemAlias { throw SafeFileError.symlink(alias) }
            }
            path.deleteLastPathComponent()
        }
    }

    /// Creates the folder (and parents) with mode 0700 and refuses symlinks on the way.
    public static func prepareDirectory(_ url: URL) throws {
        try check(url)
        let exists = FileManager.default.fileExists(atPath: url.path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        if !exists { try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path) }
    }

    /// Writes to a temporary sibling and renames it over `url`: readers see the old or the new
    /// file, never a part. Keeps the permissions of an existing file; new files get 0600.
    public static func write(_ data: Data, to url: URL) throws {
        try check(url)
        try prepareDirectory(url.deletingLastPathComponent())
        let previous = (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: data,
                                            attributes: [.posixPermissions: previous ?? NSNumber(value: 0o600)]) else {
            throw SafeFileError.cannotWrite(url.path)
        }
        guard rename(temporary.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}

/// An exclusive `flock` held for the lifetime of the object.
///
/// A nonblocking lock in Application Support is the single-instance check of an app:
/// `try FileLock(url: paths.file("app.lock"), nonblocking: true)` fails while another copy runs.
public final class FileLock {
    private let descriptor: Int32

    public init(url: URL, nonblocking: Bool = false,
                busyMessage: String = "Another copy is already running or another installation is in progress") throws {
        try SafeFile.prepareDirectory(url.deletingLastPathComponent())
        try SafeFile.check(url)
        descriptor = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw SafeFileError.cannotLock(url.path) }
        guard flock(descriptor, LOCK_EX | (nonblocking ? LOCK_NB : 0)) == 0 else {
            close(descriptor)
            throw SafeFileError.locked(busyMessage)
        }
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
