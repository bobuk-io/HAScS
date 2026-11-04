import Foundation

public enum HomeAssistantError: LocalizedError, Equatable {
    case unauthorized
    case response(Int)
    case invalidResponse
    case invalidData
    case network

    public var errorDescription: String? {
        switch self {
        case .unauthorized: L10n.string("Home Assistant rejected the token. Check the access token in Settings.")
        case .response(let status): L10n.httpError(status)
        case .invalidResponse: L10n.string("Invalid response from Home Assistant.")
        case .invalidData: L10n.string("Unable to read the Home Assistant scene list.")
        case .network: L10n.string("Unable to connect to Home Assistant. Check the connection and server URL in Settings.")
        }
    }
}

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// Never forward the bearer token to a redirect target, including same-host redirects.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct SecureURLSessionTransport: HTTPTransport {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.urlCache = nil
        config.httpCookieStorage = nil
        session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

public struct HomeAssistantClient: Sendable {
    private let configuration: Configuration
    private let transport: any HTTPTransport
    public init(configuration: Configuration, transport: any HTTPTransport = SecureURLSessionTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    public func fetchScenes() async throws -> [HAScene] {
        let data = try await request(path: ["api", "states"], method: "GET")
        // A malformed unrelated entity must not prevent scenes from loading.
        do {
            let objects = try JSONSerialization.jsonObject(with: data)
            guard let list = objects as? [[String: Any]] else { throw HomeAssistantError.invalidData }
            let sceneObjects = list.filter { ($0["entity_id"] as? String)?.hasPrefix("scene.") == true }
            let sceneData = try JSONSerialization.data(withJSONObject: sceneObjects)
            return try JSONDecoder().decode([HAScene].self, from: sceneData)
        } catch { throw HomeAssistantError.invalidData }
    }

    public func activate(sceneID: String) async throws {
        guard sceneID.hasPrefix("scene."), sceneID.count > "scene.".count else { throw HomeAssistantError.invalidData }
        let body = try JSONEncoder().encode(["entity_id": sceneID])
        _ = try await request(path: ["api", "services", "scene", "turn_on"], method: "POST", body: body)
    }

    private func request(path: [String], method: String, body: Data? = nil) async throws -> Data {
        var url = configuration.baseURL
        for component in path { url.appendPathComponent(component) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let data: Data
        let response: URLResponse
        do { (data, response) = try await transport.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw HomeAssistantError.network }
        guard let http = response as? HTTPURLResponse else { throw HomeAssistantError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw HomeAssistantError.unauthorized }
            throw HomeAssistantError.response(http.statusCode)
        }
        return data
    }
}
