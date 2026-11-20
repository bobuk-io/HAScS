// Watches one file for changes from any editor, from Ting's config store: the folder (editors
// often replace the file) and the file itself (in-place saves), coalescing the burst of one save.
import Darwin
import Foundation

@MainActor
public final class FileWatcher {
    public let url: URL
    /// True for a folder watcher: the folder and every file directly in it.
    public let watchesFolder: Bool
    private let debounce: TimeInterval
    private let onChange: () -> Void
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var folderFileSources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?

    /// Watches one file. Starts at once; the file may not exist yet, its folder must.
    public init(url: URL, debounce: TimeInterval = 0.15, onChange: @escaping () -> Void) {
        self.url = url
        watchesFolder = false
        self.debounce = debounce
        self.onChange = onChange
        directorySource = makeSource(path: url.deletingLastPathComponent().path)
        watchFile()
    }

    /// Watches a folder and every file directly in it: added, removed, renamed and edited files
    /// (Ting's micro-apps folder). The file list is read again after each change.
    public init(folder: URL, debounce: TimeInterval = 0.15, onChange: @escaping () -> Void) {
        url = folder
        watchesFolder = true
        self.debounce = debounce
        self.onChange = onChange
        directorySource = makeSource(path: folder.path)
        watchFile()
    }

    deinit {
        directorySource?.cancel()
        fileSource?.cancel()
        for source in folderFileSources { source.cancel() }
        pending?.cancel()
    }

    /// Call after the app itself wrote the file: an atomic write replaced the watched inode.
    public func fileWasReplaced() { watchFile() }

    public func stop() {
        directorySource?.cancel()
        fileSource?.cancel()
        for source in folderFileSources { source.cancel() }
        pending?.cancel()
        directorySource = nil
        fileSource = nil
        folderFileSources = []
    }

    private func watchFile() {
        guard watchesFolder else {
            fileSource?.cancel()
            fileSource = makeSource(path: url.path)
            return
        }
        for source in folderFileSources { source.cancel() }
        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        folderFileSources = files.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .compactMap { makeSource(path: $0.path) }
    }

    private func makeSource(path: String) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                               eventMask: [.write, .delete, .rename, .extend],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.schedule() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.watchFile()
                self.onChange()
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
