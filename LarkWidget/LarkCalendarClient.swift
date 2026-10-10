import Foundation

enum LarkCalendarError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case accessTokenExpired
    case api(code: Int, message: String)
    case emptyPayload
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: return "The Feishu API URL is invalid."
        case .invalidResponse: return "Feishu returned an invalid response."
        case .accessTokenExpired:
            return "Feishu access token expired or was revoked. Re-authorize Feishu and update it in Settings."
        case let .api(_, message): return message
        case .emptyPayload: return "Feishu returned no calendar data."
        case let .decoding(message): return message
        }
    }
}

struct LarkCalendarClient: Sendable {
    let configuration: LarkCalendarConfiguration
    private let session: URLSession

    init(configuration: LarkCalendarConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func events(for day: Date, calendar: Calendar = .autoupdatingCurrent) async throws -> [CalendarEvent] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(604_800)
        return try await events(from: start, to: end, calendar: calendar)
    }

    func events(from startDate: Date, to endDate: Date, calendar: Calendar = .autoupdatingCurrent) async throws -> [CalendarEvent] {
        guard configuration.isReady else { return [] }
        guard var components = URLComponents(string: configuration.baseURL) else {
            throw LarkCalendarError.invalidBaseURL
        }

        let start = calendar.startOfDay(for: startDate)
        let end = max(endDate, start.addingTimeInterval(86_400))
        let encodedCalendarID = configuration.calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? configuration.calendarID
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .appending("/open-apis/calendar/v4/calendars/")
            .appending(encodedCalendarID)
            .appending("/events/instance_view")
        // The list endpoint returns recurring masters and exceptions, not the
        // occurrences shown in a week. Let Feishu expand recurrence and moves.
        components.queryItems = [
            URLQueryItem(name: "start_time", value: String(Int(start.timeIntervalSince1970))),
            URLQueryItem(name: "end_time", value: String(Int(end.timeIntervalSince1970)))
        ]
        guard let url = components.url else { throw LarkCalendarError.invalidBaseURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw LarkCalendarError.invalidResponse }
        let envelope = try? JSONDecoder().decode(LarkAPIErrorEnvelope.self, from: data)
        let responseMessage = envelope?.msg?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard (200..<300).contains(httpResponse.statusCode) else {
            if Self.isAccessTokenError(statusCode: httpResponse.statusCode, message: responseMessage) {
                throw LarkCalendarError.accessTokenExpired
            }
            throw LarkCalendarError.api(
                code: envelope?.code ?? httpResponse.statusCode,
                message: responseMessage ?? "Lark returned HTTP \(httpResponse.statusCode)."
            )
        }
        if let code = envelope?.code, code != 0 {
            if Self.isAccessTokenError(statusCode: httpResponse.statusCode, message: responseMessage) {
                throw LarkCalendarError.accessTokenExpired
            }
            throw LarkCalendarError.api(code: code, message: responseMessage ?? "Lark returned an error.")
        }

        let decoded: LarkCalendarEventResponse
        do {
            decoded = try JSONDecoder().decode(LarkCalendarEventResponse.self, from: data)
        } catch let error as DecodingError {
            throw LarkCalendarError.decoding(LarkCalendarEventResponse.decodingErrorDescription(error))
        }
        if let code = decoded.code, code != 0 {
            let message = decoded.msg?.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.isAccessTokenError(statusCode: httpResponse.statusCode, message: message) {
                throw LarkCalendarError.accessTokenExpired
            }
            throw LarkCalendarError.api(code: code, message: message ?? "Lark returned an error.")
        }
        guard let remoteEvents = decoded.data?.items else { throw LarkCalendarError.emptyPayload }

        var uniqueEvents: [String: CalendarEvent] = [:]
        for event in remoteEvents.compactMap({ $0.makeEvent() }) {
            guard event.start < end, event.end > start else { continue }
            uniqueEvents[event.id] = event
        }

        return uniqueEvents.values.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.id < $1.id
        }
    }

    func calendars() async throws -> [FeishuCalendar] {
        guard !configuration.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LarkCalendarError.accessTokenExpired
        }

        var pageToken: String?
        var loadedCalendars: [FeishuCalendar] = []

        repeat {
            guard var components = URLComponents(string: configuration.baseURL) else {
                throw LarkCalendarError.invalidBaseURL
            }
            components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .appending("/open-apis/calendar/v4/calendars")
            var queryItems = [URLQueryItem(name: "page_size", value: "100")]
            if let pageToken, !pageToken.isEmpty {
                queryItems.append(URLQueryItem(name: "page_token", value: pageToken))
            }
            components.queryItems = queryItems

            guard let url = components.url else { throw LarkCalendarError.invalidBaseURL }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LarkCalendarError.invalidResponse
            }

            let envelope = try? JSONDecoder().decode(LarkAPIErrorEnvelope.self, from: data)
            let responseMessage = envelope?.msg?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (200..<300).contains(httpResponse.statusCode) else {
                if Self.isAccessTokenError(statusCode: httpResponse.statusCode, message: responseMessage) {
                    throw LarkCalendarError.accessTokenExpired
                }
                throw LarkCalendarError.api(
                    code: envelope?.code ?? httpResponse.statusCode,
                    message: responseMessage ?? "Lark returned HTTP \(httpResponse.statusCode)."
                )
            }
            if let code = envelope?.code, code != 0 {
                if Self.isAccessTokenError(statusCode: httpResponse.statusCode, message: responseMessage) {
                    throw LarkCalendarError.accessTokenExpired
                }
                throw LarkCalendarError.api(code: code, message: responseMessage ?? "Lark returned an error.")
            }

            let decoded: LarkCalendarListResponse
            do {
                decoded = try JSONDecoder().decode(LarkCalendarListResponse.self, from: data)
            } catch let error as DecodingError {
                throw LarkCalendarError.decoding(Self.decodingErrorDescription(error))
            }
            guard decoded.code == 0 else {
                throw LarkCalendarError.api(code: decoded.code, message: decoded.msg)
            }

            loadedCalendars.append(contentsOf: decoded.data.calendarList.filter { $0.isDeleted != true })
            if decoded.data.hasMore == true, let nextPageToken = decoded.data.pageToken, !nextPageToken.isEmpty {
                pageToken = nextPageToken
            } else {
                pageToken = nil
            }
        } while pageToken != nil

        var uniqueCalendars: [String: FeishuCalendar] = [:]
        for calendar in loadedCalendars {
            uniqueCalendars[calendar.calendarID] = calendar
        }
        return uniqueCalendars.values.sorted {
            if $0.isPrimary != $1.isPrimary { return $0.isPrimary }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private static func isAccessTokenError(statusCode: Int, message: String?) -> Bool {
        guard statusCode == 401 || message != nil else { return false }
        if statusCode == 401 { return true }

        let normalized = message?.lowercased() ?? ""
        let tokenTerms = ["access token", "user_access_token", "令牌", "token"]
        let invalidTerms = ["expired", "expire", "invalid", "revoked", "unauthorized", "过期", "无效", "失效"]
        return tokenTerms.contains(where: normalized.contains) && invalidTerms.contains(where: normalized.contains)
    }

    private static func decodingErrorDescription(_ error: DecodingError) -> String {
        let context: DecodingError.Context
        switch error {
        case let .dataCorrupted(value): context = value
        case let .keyNotFound(_, value): context = value
        case let .typeMismatch(_, value): context = value
        case let .valueNotFound(_, value): context = value
        @unknown default:
            return "Feishu returned an unexpected calendar list response."
        }
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? context.debugDescription : "Feishu response field \(path): \(context.debugDescription)"
    }
}

private struct LarkAPIErrorEnvelope: Decodable {
    let code: Int?
    let msg: String?
}
