import Foundation

// Standalone regression runner: see README for the compile/run command.
private final class FixtureProtocol: URLProtocol {
    static var body = Data()
    static var status = 200
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
private struct CalendarClientTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func main() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28))!
        func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day))!
        }
        let semester = date(2026, 9, 2, in: calendar)
        check(SchoolWeek.number(for: date(2026, 8, 31, in: calendar), semesterStart: semester, calendar: calendar) == 1, "Week containing a midweek semester start is Week 1")
        check(SchoolWeek.number(for: date(2026, 9, 6, in: calendar), semesterStart: semester, calendar: calendar) == 1, "Sunday stays in Week 1")
        check(SchoolWeek.number(for: date(2026, 9, 7, in: calendar), semesterStart: semester, calendar: calendar) == 2, "Monday advances the school week")
        check(SchoolWeek.number(for: date(2026, 8, 30, in: calendar), semesterStart: semester, calendar: calendar) == nil, "Dates before semester must not show zero or negative school weeks")
        check(SchoolWeek.number(for: date(2027, 1, 4, in: calendar), semesterStart: date(2026, 12, 28, in: calendar), calendar: calendar) == 2, "School weeks continue across calendar years")
        var dstCalendar = calendar
        dstCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        check(SchoolWeek.number(for: date(2026, 3, 9, in: dstCalendar), semesterStart: date(2026, 3, 2, in: dstCalendar), calendar: dstCalendar) == 2, "DST must not shorten a school week")
        print("PASS: school weeks, Monday/Sunday boundaries, midweek start, pre-semester, year rollover, DST")
        let end = calendar.date(byAdding: .day, value: 7, to: start)!
        let base = Int(start.timeIntervalSince1970)
        func event(_ id: String, _ offset: Int, title: String = "Class", status: String = "confirmed") -> [String: Any] {
            ["event_id": id, "summary": title, "status": status,
             "start_time": ["timestamp": String(base + offset)],
             "end_time": ["timestamp": String(base + offset + 5400)]]
        }
        func fixture(_ object: [String: Any], status: Int = 200) throws {
            FixtureProtocol.body = try JSONSerialization.data(withJSONObject: object)
            FixtureProtocol.status = status
            FixtureProtocol.requests = []
        }
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        let client = LarkCalendarClient(configuration: LarkCalendarConfiguration(
            token: "fixture-only", calendarID: "fixture@calendar", baseURL: "https://calendar.test", uses24HourTime: true
        ), session: session)

        var monday = event("recurring", 30600, title: "Monday class")
        monday["location"] = ["name": " 教学楼阶一5 ", "address": "Campus address"]
        var wednesday = event("recurring", 2 * 86400 + 30600, title: "Wednesday class")
        wednesday["location"] = ["name": "  ", "address": "\n"]
        var moved = event("exception", 86400 + 37500, title: "Moved class")
        moved["is_exception"] = true
        moved["recurring_event_id"] = "recurring"
        moved["location"] = ["name": "", "address": " 教学楼412 "]
        let allDay: [String: Any] = ["event_id": "all-day", "summary": "Holiday",
                                    "start_time": ["date": "2026-10-01", "timezone": "Asia/Shanghai"],
                                    "end_time": ["date": "2026-10-02", "timezone": "Asia/Shanghai"]]
        let items: [[String: Any]] = [
            wednesday, monday, monday, moved, allDay,
            event("cancelled-with-times", 48600, title: "", status: "cancelled"),
            ["event_id": "cancelled-without-times", "status": "cancelled"],
            event("before-window", -86400), event("at-window-end", 7 * 86400)
        ]
        try fixture(["code": 0, "data": ["items": items]])
        let events = try await client.events(for: start, calendar: calendar)
        check(events.map(\.title) == ["Monday class", "Moved class", "Wednesday class", "Holiday"], "Keep concrete occurrences and moved exceptions; remove cancellations, duplicates and out-of-range events")
        check(Set(events.map(\.id)).count == 4, "Recurring occurrences must have distinct identities")
        check(events.last!.isAllDay, "Preserve all-day events")
        check(events.map(\.location) == ["教学楼阶一5", "教学楼412", nil, nil], "Use trimmed location name, fall back to address, and omit empty or missing locations")
        print("PASS: location names, address fallback, blank and missing locations")
        check(events[1].start == Date(timeIntervalSince1970: Double(base + 86400 + 37500)), "Preserve moved occurrence time")
        check(FixtureProtocol.requests.count == 1, "Instance view has no list pagination")
        let request = FixtureProtocol.requests[0]
        check(request.httpMethod == "GET", "Use read-only request")
        check(request.url!.path == "/open-apis/calendar/v4/calendars/fixture@calendar/events/instance_view", "Fetch expanded calendar view, not recurring masters")
        let query = Dictionary(uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        check(query == ["start_time": String(base), "end_time": String(Int(end.timeIntervalSince1970))], "Request exactly the visible week without unsupported list parameters")
        print("PASS: expanded occurrences, exceptions, cancellations, deduplication, range, request contract")

        try fixture(["code": 0, "data": ["items": []]])
        let empty = try await client.events(for: start, calendar: calendar)
        check(empty.isEmpty, "A valid empty calendar must succeed")
        print("PASS: empty calendar")

        try fixture(["code": 0])
        do {
            _ = try await client.events(for: start, calendar: calendar)
            preconditionFailure("Missing payload must not report a successful sync")
        } catch LarkCalendarError.emptyPayload {}
        print("PASS: missing payload fails sync")

        try fixture(["code": 99991663, "msg": "access token expired"], status: 401)
        do {
            _ = try await client.events(for: start, calendar: calendar)
            preconditionFailure("Expired token must trigger refresh")
        } catch LarkCalendarError.accessTokenExpired {}
        print("PASS: expired token")

        try fixture(["code": 191003, "msg": "permission denied"])
        do {
            _ = try await client.events(for: start, calendar: calendar)
            preconditionFailure("API errors must not report a successful sync")
        } catch LarkCalendarError.api(let code, _) {
            check(code == 191003, "Preserve API error code")
        }
        print("PASS: API failure")
    }
}
