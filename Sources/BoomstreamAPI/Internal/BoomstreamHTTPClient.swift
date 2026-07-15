import Foundation

/// Retry: 5xx + network errors, exponential backoff, max 3 попытки
/// (docs/SDK_ARCHITECTURE.md §7). Все вызовы SDK — идемпотентные read-запросы.
struct RetryPolicy: Sendable {
    var maxAttempts: Int = 3
    var baseDelay: TimeInterval = 0.5

    func delay(afterAttempt attempt: Int) -> TimeInterval {
        baseDelay * pow(2, Double(attempt - 1))
    }
}

/// Общий URLSession-слой обоих клиентов: заголовки, таймауты, retry, маппинг ошибок.
/// Единый системный сетевой стек (URLSession) — тот же, что использует AVFoundation.
final class BoomstreamHTTPClient: Sendable {
    private let session: URLSession
    private let defaultHeaders: [String: String]
    private let retryPolicy: RetryPolicy

    init(
        headers: [String: String],
        connectTimeout: TimeInterval,
        resourceTimeout: TimeInterval,
        retryPolicy: RetryPolicy = RetryPolicy(),
        sessionConfiguration: URLSessionConfiguration = .ephemeral
    ) {
        sessionConfiguration.timeoutIntervalForRequest = connectTimeout
        sessionConfiguration.timeoutIntervalForResource = resourceTimeout
        self.session = URLSession(configuration: sessionConfiguration)
        self.defaultHeaders = headers
        self.retryPolicy = retryPolicy
    }

    func get<Response: Decodable>(_ url: URL, errorPath: String) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await performJSON(request, errorPath: errorPath)
    }

    func postJSON<Body: Encodable, Response: Decodable>(
        _ url: URL,
        body: Body,
        errorPath: String
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw BoomstreamError.unknown(underlying: error)
        }
        return try await performJSON(request, errorPath: errorPath)
    }

    private func performJSON<Response: Decodable>(
        _ request: URLRequest,
        errorPath: String
    ) async throws -> Response {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in defaultHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await send(request)
        guard (200...299).contains(response.statusCode) else {
            throw Self.mapHTTPError(statusCode: response.statusCode, data: data, path: errorPath)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw BoomstreamError.unknown(underlying: error)
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var attempt = 1
        while true {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw BoomstreamError.unknown(underlying: nil)
                }
                if (500...599).contains(http.statusCode), attempt < retryPolicy.maxAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(retryPolicy.delay(afterAttempt: attempt) * 1_000_000_000))
                    attempt += 1
                    continue
                }
                return (data, http)
            } catch let error as BoomstreamError {
                throw error
            } catch {
                if error is URLError, attempt < retryPolicy.maxAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(retryPolicy.delay(afterAttempt: attempt) * 1_000_000_000))
                    attempt += 1
                    continue
                }
                throw BoomstreamError.network(underlying: error)
            }
        }
    }

    /// Маппинг HTTP-статусов: 401/403 → unauthorised, 404 → mediaNotFound(path),
    /// прочие — http(status, body).
    static func mapHTTPError(statusCode: Int, data: Data, path: String) -> BoomstreamError {
        switch statusCode {
        case 401, 403:
            return .unauthorised
        case 404:
            return .mediaNotFound(mediaCode: path)
        default:
            return .http(statusCode: statusCode, body: String(data: data.prefix(1024), encoding: .utf8))
        }
    }
}
