import AppKit
import Foundation
import Network

struct FeishuOAuthTokens: Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let refreshTokenExpiresIn: Int?
}

enum LarkOAuthError: LocalizedError {
    case invalidConfiguration
    case cancelled
    case callbackTimeout
    case invalidCallback
    case listenerFailed(String)
    case stateMismatch
    case api(code: Int?, message: String)
    case invalidTokenResponse

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "OAuth is not configured. Check the Feishu app ID, app secret, and localhost redirect URI."
        case .cancelled:
            return "Feishu sign-in was cancelled."
        case .callbackTimeout:
            return "Feishu sign-in timed out. Start sign-in again if you still need access."
        case .invalidCallback:
            return "Feishu returned an invalid OAuth callback."
        case let .listenerFailed(message):
            return "Could not start the local OAuth callback listener. \(message)"
        case .stateMismatch:
            return "The Feishu OAuth state did not match. Please try again."
        case let .api(_, message):
            return message
        case .invalidTokenResponse:
            return "Feishu did not return a usable access token."
        }
    }
}

@MainActor
final class LarkOAuthService {
    func authorize(
        clientID: String,
        clientSecret: String,
        baseURL: String,
        redirectURI: String
    ) async throws -> FeishuOAuthTokens {
        guard !clientID.isEmpty, !clientSecret.isEmpty,
              let redirectURL = URL(string: redirectURI),
              redirectURL.scheme == "http",
              redirectURL.host == "localhost",
              redirectURL.port != nil else {
            throw LarkOAuthError.invalidConfiguration
        }

        let state = UUID().uuidString
        let authorizationURL = try makeAuthorizationURL(
            clientID: clientID,
            redirectURI: redirectURI,
            state: state
        )

        let receiver = try LoopbackCallbackReceiver(redirectURL: redirectURL)
        try await receiver.start()
        defer { receiver.cancel() }

        guard NSWorkspace.shared.open(authorizationURL) else {
            throw LarkOAuthError.invalidConfiguration
        }

        let callbackURL = try await receiver.wait(timeout: 300)
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw LarkOAuthError.invalidCallback
        }

        let queryItems = components.queryItems ?? []
        guard queryItems.first(where: { $0.name == "state" })?.value == state else {
            throw LarkOAuthError.stateMismatch
        }
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            let description = queryItems.first(where: { $0.name == "error_description" })?.value ?? error
            throw LarkOAuthError.api(code: nil, message: "Feishu sign-in failed: \(description)")
        }
        guard let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw LarkOAuthError.invalidCallback
        }

        return try await exchange(
            grantType: "authorization_code",
            code: code,
            refreshToken: nil,
            clientID: clientID,
            clientSecret: clientSecret,
            baseURL: baseURL,
            redirectURI: redirectURI
        )
    }

    func refresh(
        clientID: String,
        clientSecret: String,
        refreshToken: String,
        baseURL: String
    ) async throws -> FeishuOAuthTokens {
        try await exchange(
            grantType: "refresh_token",
            code: nil,
            refreshToken: refreshToken,
            clientID: clientID,
            clientSecret: clientSecret,
            baseURL: baseURL,
            redirectURI: nil
        )
    }

    private func makeAuthorizationURL(
        clientID: String,
        redirectURI: String,
        state: String
    ) throws -> URL {
        guard var components = URLComponents(string: "https://accounts.feishu.cn") else {
            throw LarkOAuthError.invalidConfiguration
        }
        components.path = "/open-apis/authen/v1/authorize"
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "calendar:calendar:readonly offline_access"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = components.url else { throw LarkOAuthError.invalidConfiguration }
        return url
    }

    private func exchange(
        grantType: String,
        code: String?,
        refreshToken: String?,
        clientID: String,
        clientSecret: String,
        baseURL: String,
        redirectURI: String?
    ) async throws -> FeishuOAuthTokens {
        guard var components = URLComponents(string: baseURL) else {
            throw LarkOAuthError.invalidConfiguration
        }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .appending("/open-apis/authen/v2/oauth/token")
        guard let url = components.url else { throw LarkOAuthError.invalidConfiguration }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var body: [String: String] = [
            "grant_type": grantType,
            "client_id": clientID,
            "client_secret": clientSecret
        ]
        if let code { body["code"] = code }
        if let refreshToken { body["refresh_token"] = refreshToken }
        if let redirectURI { body["redirect_uri"] = redirectURI }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LarkOAuthError.api(code: nil, message: "Feishu returned an invalid OAuth response.")
        }

        let envelope: FeishuOAuthResponse
        do {
            envelope = try JSONDecoder().decode(FeishuOAuthResponse.self, from: data)
        } catch {
            if !(200..<300).contains(httpResponse.statusCode) {
                throw LarkOAuthError.api(
                    code: httpResponse.statusCode,
                    message: "Feishu OAuth returned HTTP \(httpResponse.statusCode)."
                )
            }
            throw LarkOAuthError.invalidTokenResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LarkOAuthError.api(
                code: envelope.code,
                message: envelope.errorDescription ?? envelope.error ?? "Feishu OAuth returned HTTP \(httpResponse.statusCode)."
            )
        }
        if envelope.code != 0 {
            throw LarkOAuthError.api(
                code: envelope.code,
                message: envelope.errorDescription ?? envelope.error ?? "Feishu OAuth failed."
            )
        }
        guard let accessToken = envelope.accessToken,
              !accessToken.isEmpty,
              let expiresIn = envelope.expiresIn else {
            throw LarkOAuthError.invalidTokenResponse
        }
        return FeishuOAuthTokens(
            accessToken: accessToken,
            refreshToken: envelope.refreshToken,
            expiresIn: expiresIn,
            refreshTokenExpiresIn: envelope.refreshTokenExpiresIn
        )
    }
}

private final class LoopbackCallbackReceiver: @unchecked Sendable {
    private let redirectURL: URL
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.xiaodai.feishu-calendar.oauth-loopback")
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var pendingResult: Result<URL, Error>?
    private var startupContinuation: CheckedContinuation<Void, Error>?
    private var startupResult: Result<Void, Error>?

    init(redirectURL: URL) throws {
        guard let portValue = redirectURL.port,
              let port = NWEndpoint.Port(rawValue: UInt16(portValue)) else {
            throw LarkOAuthError.invalidConfiguration
        }
        self.redirectURL = redirectURL
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        listener = try NWListener(using: parameters, on: port)
    }

    func start() async throws {
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.finishStartup(.success(()))
            case let .failed(error):
                let failure = LarkOAuthError.listenerFailed(error.localizedDescription)
                self.finishStartup(.failure(failure))
                self.finish(.failure(failure))
            case .cancelled:
                self.finishStartup(.failure(LarkOAuthError.cancelled))
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.receive(from: connection)
        }

        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let startupResult {
                lock.unlock()
                continuation.resume(with: startupResult)
            } else {
                startupContinuation = continuation
                lock.unlock()
                listener.start(queue: queue)
            }
        }
    }

    func wait() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let pendingResult {
                lock.unlock()
                continuation.resume(with: pendingResult)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func wait(timeout: TimeInterval) async throws -> URL {
        let timeoutWork = DispatchWorkItem { [weak self] in
            self?.finish(.failure(LarkOAuthError.callbackTimeout))
        }
        queue.asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
        defer { timeoutWork.cancel() }
        return try await wait()
    }

    func cancel() {
        listener.cancel()
        finishStartup(.failure(LarkOAuthError.cancelled))
        finish(.failure(LarkOAuthError.cancelled))
    }

    private func receive(from connection: NWConnection) {
        var buffer = Data()
        var hasStartedReading = false

        func readNext() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let error {
                    connection.cancel()
                    self.finish(.failure(error))
                    return
                }
                if let data {
                    buffer.append(data)
                }
                if let callbackURL = self.callbackURL(from: buffer) {
                    self.sendSuccess(to: connection)
                    self.finish(.success(callbackURL))
                    return
                }
                if isComplete || buffer.count > 64 * 1024 {
                    connection.cancel()
                    self.finish(.failure(LarkOAuthError.invalidCallback))
                    return
                }
                readNext()
            }
        }

        connection.stateUpdateHandler = { [weak self] state in
            guard self != nil, case .ready = state, !hasStartedReading else { return }
            hasStartedReading = true
            readNext()
        }
        connection.start(queue: queue)
    }

    private func callbackURL(from data: Data) -> URL? {
        guard let request = String(data: data, encoding: .utf8),
              let requestLine = request.components(separatedBy: "\r\n").first else {
            return nil
        }
        let fields = requestLine.split(separator: " ")
        guard fields.count >= 2, fields[0] == "GET" else { return nil }
        let target = String(fields[1])
        guard let targetURL = URL(string: target),
              targetURL.path == redirectURL.path else {
            return nil
        }
        var components = URLComponents(url: redirectURL, resolvingAgainstBaseURL: false)
        components?.query = targetURL.query
        return components?.url
    }

    private func sendSuccess(to connection: NWConnection) {
        let body = "<html><body>You can return to Feishu Calendar.</body></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(_ result: Result<URL, Error>) {
        listener.cancel()
        lock.lock()
        guard continuation != nil || pendingResult == nil else {
            lock.unlock()
            return
        }
        let continuation = self.continuation
        self.continuation = nil
        if continuation == nil { pendingResult = result }
        lock.unlock()
        continuation?.resume(with: result)
    }

    private func finishStartup(_ result: Result<Void, Error>) {
        lock.lock()
        guard startupContinuation != nil || startupResult == nil else {
            lock.unlock()
            return
        }
        let continuation = startupContinuation
        startupContinuation = nil
        if continuation == nil { startupResult = result }
        lock.unlock()
        continuation?.resume(with: result)
    }
}

private struct FeishuOAuthResponse: Decodable {
    let code: Int
    let accessToken: String?
    let expiresIn: Int?
    let refreshToken: String?
    let refreshTokenExpiresIn: Int?
    let tokenType: String?
    let scope: String?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case code
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case refreshTokenExpiresIn = "refresh_token_expires_in"
        case tokenType = "token_type"
        case scope
        case error
        case errorDescription = "error_description"
    }
}
