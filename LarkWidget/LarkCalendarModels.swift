import Foundation

enum SchoolWeek {
    static func number(for date: Date, semesterStart: Date, calendar: Calendar = .autoupdatingCurrent) -> Int? {
        var calendar = calendar
        calendar.firstWeekday = 2
        guard let firstWeek = calendar.dateInterval(of: .weekOfYear, for: semesterStart)?.start,
              let visibleWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
              visibleWeek >= firstWeek,
              let days = calendar.dateComponents([.day], from: firstWeek, to: visibleWeek).day else { return nil }
        return days / 7 + 1
    }
}

struct LarkCalendarConfiguration: Sendable, Equatable {
    var token: String
    var calendarID: String
    var baseURL: String
    var uses24HourTime: Bool

    static let `default` = LarkCalendarConfiguration(
        token: "",
        calendarID: "",
        baseURL: "https://open.feishu.cn",
        uses24HourTime: true
    )

    var isReady: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !calendarID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct FeishuCalendar: Identifiable, Decodable, Hashable, Sendable {
    let calendarID: String
    let summary: String?
    let description: String?
    let permissions: String?
    let color: Int?
    let type: String?
    let isDeleted: Bool?
    let isThirdParty: Bool?
    let summaryAlias: String?
    let role: String?

    var id: String { calendarID }

    var isPrimary: Bool { type == "primary" }

    var displayName: String {
        let trimmedSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = trimmedSummary.isEmpty ? calendarID : trimmedSummary
        let trimmedAlias = summaryAlias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedAlias.isEmpty || trimmedAlias == title ? title : "\(title) - \(trimmedAlias)"
    }

    enum CodingKeys: String, CodingKey {
        case calendarID = "calendar_id"
        case summary
        case description
        case permissions
        case color
        case type
        case summaryAlias = "summary_alias"
        case isDeleted = "is_deleted"
        case isThirdParty = "is_third_party"
        case role
    }

}

struct LarkCalendarListResponse: Decodable, Sendable {
    let code: Int
    let msg: String
    let data: Payload

    struct Payload: Decodable, Sendable {
        let calendarList: [FeishuCalendar]
        let hasMore: Bool?
        let pageToken: String?
        let syncToken: String?

        enum CodingKeys: String, CodingKey {
            case calendarList = "calendar_list"
            case hasMore = "has_more"
            case pageToken = "page_token"
            case syncToken = "sync_token"
        }
    }
}

struct CalendarEvent: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let notes: String?
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Int?
    let timezone: String?
    var location: String? = nil

    var duration: TimeInterval {
        max(end.timeIntervalSince(start), 0)
    }

    var isInProgress: Bool {
        state(at: .now) == .ongoing
    }

    func state(at date: Date) -> CalendarEventState {
        if isAllDay && Calendar.autoupdatingCurrent.isDate(date, inSameDayAs: start) {
            return .ongoing
        }
        if end <= date { return .passed }
        if start <= date { return .ongoing }
        return .upcoming
    }

    static let preview: [CalendarEvent] = [
        CalendarEvent(
            id: "design-review",
            title: "Product design review",
            notes: "Review the new calendar surface",
            start: Calendar.current.date(bySettingHour: 9, minute: 30, second: 0, of: .now) ?? .now,
            end: Calendar.current.date(bySettingHour: 10, minute: 15, second: 0, of: .now) ?? .now.addingTimeInterval(2_700),
            isAllDay: false,
            color: 0,
            timezone: TimeZone.current.identifier
        ),
        CalendarEvent(
            id: "focus-block",
            title: "Focus block",
            notes: nil,
            start: Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: .now) ?? .now,
            end: Calendar.current.date(bySettingHour: 12, minute: 30, second: 0, of: .now) ?? .now.addingTimeInterval(5_400),
            isAllDay: false,
            color: 1,
            timezone: TimeZone.current.identifier
        ),
        CalendarEvent(
            id: "team-lunch",
            title: "Team lunch",
            notes: nil,
            start: Calendar.current.date(bySettingHour: 12, minute: 45, second: 0, of: .now) ?? .now,
            end: Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: .now) ?? .now.addingTimeInterval(4_500),
            isAllDay: false,
            color: 2,
            timezone: TimeZone.current.identifier
        )
    ]
}

enum CalendarEventState: Int, Sendable {
    case ongoing = 0
    case upcoming = 1
    case passed = 2

    var label: String {
        switch self {
        case .ongoing: return "NOW"
        case .upcoming: return "UP NEXT"
        case .passed: return "DONE"
        }
    }

    var shortLabel: String {
        switch self {
        case .ongoing: return "NOW"
        case .upcoming: return "NEXT"
        case .passed: return "DONE"
        }
    }
}

struct LarkCalendarEventResponse: Decodable, Sendable {
    let code: Int?
    let msg: String?
    let data: Payload?

    struct Payload: Decodable, Sendable {
        let items: [RemoteEvent]?
        let hasMore: Bool?
        let pageToken: String?
        let syncToken: String?

        enum CodingKeys: String, CodingKey {
            case items
            case hasMore = "has_more"
            case pageToken = "page_token"
            case syncToken = "sync_token"
        }
    }

    struct RemoteEvent: Decodable, Sendable {
        let eventID: String
        let summary: String?
        let description: String?
        let startTime: CalendarTimeValue?
        let endTime: CalendarTimeValue?
        let status: String?
        let color: Int?
        let location: Location?

        struct Location: Decodable, Sendable {
            let name: String?
            let address: String?

            var displayName: String? {
                [name, address]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty }
            }
        }

        enum CodingKeys: String, CodingKey {
            case eventID = "event_id"
            case summary
            case description
            case startTime = "start_time"
            case endTime = "end_time"
            case status
            case color
            case location
        }

        func makeEvent() -> CalendarEvent? {
            guard status != "cancelled",
                  let startTime, let endTime,
                  let start = startTime.date, let end = endTime.date else { return nil }
            let normalizedEnd: Date
            if startTime.isCalendarDate, end <= start {
                normalizedEnd = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            } else {
                normalizedEnd = max(end, start)
            }

            // Feishu can reuse event_id for each occurrence of a recurring event.
            // Include the occurrence bounds so SwiftUI receives a stable,
            // unique identity for every rendered event.
            let occurrenceID = [
                eventID,
                String(Int(start.timeIntervalSince1970)),
                String(Int(normalizedEnd.timeIntervalSince1970))
            ].joined(separator: ":")

            return CalendarEvent(
                id: occurrenceID,
                title: summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? summary! : "Untitled event",
                notes: description,
                start: start,
                end: normalizedEnd,
                isAllDay: startTime.isCalendarDate,
                color: color,
                timezone: startTime.timezone ?? endTime.timezone,
                location: location?.displayName
            )
        }
    }
}

struct CalendarTimeValue: Decodable, Sendable {
    let dateValue: String?
    let timestamp: String?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case dateValue = "date"
        case timestamp
        case timezone
    }

    var isCalendarDate: Bool {
        dateValue != nil && timestamp == nil
    }

    var date: Date? {
        if let timestamp, let seconds = Double(timestamp) {
            // Lark returns Unix timestamps in seconds. Millisecond timestamps are
            // accepted as well so imported calendars remain useful.
            return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1_000 : seconds)
        }

        guard let dateValue else { return nil }
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: timezone ?? "") ?? .autoupdatingCurrent
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: dateValue)
    }
}

extension LarkCalendarEventResponse {
    static func decodingErrorDescription(_ error: DecodingError) -> String {
        let context: DecodingError.Context
        switch error {
        case let .dataCorrupted(value): context = value
        case let .keyNotFound(_, value): context = value
        case let .typeMismatch(_, value): context = value
        case let .valueNotFound(_, value): context = value
        @unknown default:
            return "Feishu returned an unexpected calendar response."
        }
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? context.debugDescription : "Feishu response field \(path): \(context.debugDescription)"
    }
}
