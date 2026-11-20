// Local IPC between an app and its command-line companion through CFMessagePort, from lowkey's
// `lowkeyctl`. No XPC service, no helper and no network socket. The payload format belongs to the app.
import CoreFoundation
import Foundation

/// A named local port that answers each request synchronously on its own serial queue.
public final class MessagePortServer: @unchecked Sendable {
    public typealias Handler = @Sendable (_ messageID: Int32, _ payload: Data) -> Data

    private final class Box {
        let handler: Handler
        init(_ handler: @escaping Handler) { self.handler = handler }
    }

    private let port: CFMessagePort
    public let name: String

    /// `name` must be unique per process: use `MessagePortServer.name(prefix:pid:)`.
    /// Returns nil when the name is taken.
    public init?(name: String, queueLabel: String = "io.bobuk.message-port", handler: @escaping Handler) {
        let box = Unmanaged.passRetained(Box(handler))
        var context = CFMessagePortContext(
            version: 0, info: box.toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                _ = Unmanaged<Box>.fromOpaque(pointer).retain()
                return UnsafeRawPointer(pointer)
            },
            release: { pointer in
                guard let pointer else { return }
                Unmanaged<Box>.fromOpaque(pointer).release()
            },
            copyDescription: nil)
        let callback: CFMessagePortCallBack = { _, messageID, data, info in
            guard let info else { return nil }
            let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
            let reply = box.handler(messageID, (data as Data?) ?? Data())
            return .passRetained(reply as CFData)
        }
        let created = CFMessagePortCreateLocal(nil, name as CFString, callback, &context, nil)
        box.release() // The port retained the box through the context.
        guard let created else { return nil }
        port = created
        self.name = name
        CFMessagePortSetDispatchQueue(created, DispatchQueue(label: queueLabel))
    }

    deinit { CFMessagePortInvalidate(port) }

    /// A versioned, per-process name such as `io.bobuk.lowkey.control.v1.4242`.
    public static func name(prefix: String, version: Int = 1, pid: Int32 = getpid()) -> String {
        "\(prefix).v\(version).\(pid)"
    }

    /// Runs `work` on the main actor and waits for it at most until `deadline`. CFMessagePort needs
    /// a synchronous reply; only the port's queue waits, the main actor stays free.
    public static func replyFromMainActor(deadline: DispatchTime, fallback: Data,
                                          _ work: @escaping @MainActor @Sendable () async -> Data) -> Data {
        final class Result: @unchecked Sendable { var data: Data? }
        let result = Result()
        let done = DispatchSemaphore(value: 0)
        Task { @MainActor in
            if DispatchTime.now() < deadline { result.data = await work() }
            done.signal()
        }
        return done.wait(timeout: deadline) == .success ? (result.data ?? fallback) : fallback
    }
}

public enum MessagePortClient {
    public enum Failure: Error, Equatable {
        case notListening
        case sendFailed(Int32)
    }

    /// True when a server listens under `name`.
    public static func isListening(_ name: String) -> Bool {
        CFMessagePortCreateRemote(nil, name as CFString) != nil
    }

    /// Waits up to `timeout` for a server to appear (an app that is still starting). Stops early
    /// when `keepWaiting` turns false, for example because the launched app has quit.
    public static func waitForServer(_ name: String, timeout: TimeInterval,
                                     keepWaiting: @escaping () -> Bool = { true }) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && keepWaiting() {
            if isListening(name) { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return isListening(name)
    }

    /// Sends one request and returns the reply. Never retried: a timed-out command may already have
    /// run. `sendTimeout` bounds handing the request to a busy port; `timeout` waits for the reply.
    public static func send(_ payload: Data, to name: String, messageID: Int32 = 1,
                            sendTimeout: TimeInterval? = nil, timeout: TimeInterval) -> Result<Data, Failure> {
        guard let port = CFMessagePortCreateRemote(nil, name as CFString) else { return .failure(.notListening) }
        var response: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(port, messageID, payload as CFData, sendTimeout ?? timeout, timeout,
                                              CFRunLoopMode.defaultMode.rawValue, &response)
        guard status == kCFMessagePortSuccess, let bytes = response?.takeRetainedValue() else {
            return .failure(.sendFailed(status))
        }
        return .success(bytes as Data)
    }
}
