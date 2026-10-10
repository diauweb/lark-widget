import Foundation
import Security
import SwiftUI

@MainActor
final class LarkCalendarStore: ObservableObject {
    static let redirectURI = "http://localhost:53291/oauth/callback"

    @Published var clientID: String
    @Published var clientSecret: String
    @Published var calendarID: String
    @Published var baseURL: String
    @Published private(set) var semesterStartDate: Date?
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var calendars: [FeishuCalendar] = []
    @Published private(set) var selectedCalendarColor: Int?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingCalendars = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var calendarErrorMessage: String?
    @Published var authMessage: String?

    private let defaults: UserDefaults
    private let tokenStore: KeychainTokenStore
    private let refreshTokenStore: KeychainTokenStore
    private let clientSecretStore: KeychainTokenStore
    private let oauthService = LarkOAuthService()
    private var token: String
    private var refreshToken: String
    private var accessTokenExpiresAt: Date?
    private var refreshTokenExpiresAt: Date?
    private var refreshRequestID = 0

    init(
        defaults: UserDefaults = .standard,
        tokenStore: KeychainTokenStore = KeychainTokenStore(account: "feishu-user-access-token"),
        refreshTokenStore: KeychainTokenStore = KeychainTokenStore(account: "feishu-refresh-token"),
        clientSecretStore: KeychainTokenStore = KeychainTokenStore(account: "feishu-client-secret")
    ) {
        self.defaults = defaults
        self.tokenStore = tokenStore
        self.refreshTokenStore = refreshTokenStore
        self.clientSecretStore = clientSecretStore
        clientID = defaults.string(forKey: Keys.clientID) ?? ""
        clientSecret = (try? clientSecretStore.read()) ?? ""
        calendarID = defaults.string(forKey: Keys.calendarID) ?? ""
        selectedCalendarColor = defaults.object(forKey: Keys.selectedCalendarColor) as? Int
        baseURL = defaults.string(forKey: Keys.baseURL) ?? LarkCalendarConfiguration.default.baseURL
        semesterStartDate = defaults.object(forKey: Keys.semesterStartDate) as? Date
        token = (try? tokenStore.read()) ?? ""
        refreshToken = (try? refreshTokenStore.read()) ?? ""
        accessTokenExpiresAt = defaults.object(forKey: Keys.accessTokenExpiresAt) as? Date
        refreshTokenExpiresAt = defaults.object(forKey: Keys.refreshTokenExpiresAt) as? Date
    }

    var configuration: LarkCalendarConfiguration {
        LarkCalendarConfiguration(
            token: token.trimmingCharacters(in: .whitespacesAndNewlines),
            calendarID: calendarID.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            uses24HourTime: true
        )
    }

    var isConfigured: Bool {
        !calendarID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !refreshToken.isEmpty)
    }

    var isSignedIn: Bool {
        !token.isEmpty || !refreshToken.isEmpty
    }

    func saveCalendarSettings(calendarID: String, baseURL: String) {
        self.calendarID = calendarID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? LarkCalendarConfiguration.default.baseURL
            : baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(self.calendarID, forKey: Keys.calendarID)
        defaults.set(self.baseURL, forKey: Keys.baseURL)
        refresh()
    }

    func saveSemesterStartDate(_ date: Date) {
        let start = Calendar.autoupdatingCurrent.startOfDay(for: date)
        semesterStartDate = start
        defaults.set(start, forKey: Keys.semesterStartDate)
    }

    func selectCalendar(_ calendarID: String) {
        let cleanedCalendarID = calendarID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedCalendarID.isEmpty else { return }
        self.calendarID = cleanedCalendarID
        defaults.set(cleanedCalendarID, forKey: Keys.calendarID)
        updateSelectedCalendarColor()
        refresh()
    }

    func signIn(clientID: String, clientSecret: String) {
        let cleanedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedClientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedClientID.isEmpty, !cleanedClientSecret.isEmpty else {
            authMessage = "Enter the Feishu app ID and app secret first."
            return
        }

        do {
            try clientSecretStore.write(cleanedClientSecret)
            self.clientID = cleanedClientID
            self.clientSecret = cleanedClientSecret
            defaults.set(cleanedClientID, forKey: Keys.clientID)
            authMessage = nil
        } catch {
            authMessage = "Could not save the app secret to Keychain."
            return
        }

        isAuthenticating = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let tokens = try await oauthService.authorize(
                    clientID: cleanedClientID,
                    clientSecret: cleanedClientSecret,
                    baseURL: baseURL,
                    redirectURI: Self.redirectURI
                )
                try persist(tokens)
                isAuthenticating = false
                authMessage = "Signed in to Feishu."
                loadCalendars()
                refresh()
            } catch {
                isAuthenticating = false
                authMessage = error.localizedDescription
            }
        }
    }

    func signOut() {
        refreshRequestID += 1
        tokenStore.delete()
        refreshTokenStore.delete()
        defaults.removeObject(forKey: Keys.accessTokenExpiresAt)
        defaults.removeObject(forKey: Keys.refreshTokenExpiresAt)
        token = ""
        refreshToken = ""
        accessTokenExpiresAt = nil
        refreshTokenExpiresAt = nil
        events = []
        calendars = []
        selectedCalendarColor = nil
        defaults.removeObject(forKey: Keys.selectedCalendarColor)
        lastUpdated = nil
        isLoading = false
        errorMessage = nil
        calendarErrorMessage = nil
        authMessage = "Signed out."
    }

    func refresh(for date: Date = .now) {
        refreshRequestID += 1
        let requestID = refreshRequestID
        guard isConfigured else {
            events = []
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let loadedEvents = try await fetchEventsWithRefresh(for: date)
                guard requestID == refreshRequestID else { return }
                events = loadedEvents
                lastUpdated = .now
                errorMessage = nil
                isLoading = false
            } catch {
                guard requestID == refreshRequestID else { return }
                events = []
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func loadCalendars() {
        guard !isLoadingCalendars else { return }
        guard isSignedIn else {
            calendars = []
            calendarErrorMessage = nil
            return
        }

        isLoadingCalendars = true
        calendarErrorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let loadedCalendars = try await fetchCalendarsWithRefresh()
                calendars = loadedCalendars
                var selectedCalendarChanged = false
                if calendarID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let preferredCalendar = loadedCalendars.first(where: \.isPrimary) ?? loadedCalendars.first {
                    calendarID = preferredCalendar.calendarID
                    defaults.set(calendarID, forKey: Keys.calendarID)
                    selectedCalendarChanged = true
                }
                updateSelectedCalendarColor()
                calendarErrorMessage = nil
                isLoadingCalendars = false
                if selectedCalendarChanged {
                    refresh()
                }
            } catch {
                calendars = []
                calendarErrorMessage = error.localizedDescription
                isLoadingCalendars = false
            }
        }
    }

    private func fetchEventsWithRefresh(for date: Date) async throws -> [CalendarEvent] {
        try await refreshAccessTokenIfNeeded()
        do {
            return try await LarkCalendarClient(configuration: configuration).events(for: date)
        } catch let error as LarkCalendarError {
            guard case .accessTokenExpired = error, !refreshToken.isEmpty else { throw error }
            try await refreshAccessToken(force: true)
            return try await LarkCalendarClient(configuration: configuration).events(for: date)
        }
    }

    private func fetchCalendarsWithRefresh() async throws -> [FeishuCalendar] {
        try await refreshAccessTokenIfNeeded()
        do {
            return try await LarkCalendarClient(configuration: configuration).calendars()
        } catch let error as LarkCalendarError {
            guard case .accessTokenExpired = error, !refreshToken.isEmpty else { throw error }
            try await refreshAccessToken(force: true)
            return try await LarkCalendarClient(configuration: configuration).calendars()
        }
    }

    private func refreshAccessTokenIfNeeded() async throws {
        guard !refreshToken.isEmpty else { return }
        let refreshWindow: TimeInterval = 120
        if let accessTokenExpiresAt, accessTokenExpiresAt.timeIntervalSinceNow > refreshWindow, !token.isEmpty {
            return
        }
        try await refreshAccessToken(force: false)
    }

    private func refreshAccessToken(force: Bool) async throws {
        guard !refreshToken.isEmpty else { throw LarkCalendarError.accessTokenExpired }
        if let refreshTokenExpiresAt, refreshTokenExpiresAt <= .now {
            throw LarkCalendarError.accessTokenExpired
        }
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            throw LarkCalendarError.accessTokenExpired
        }
        if !force, let accessTokenExpiresAt, accessTokenExpiresAt.timeIntervalSinceNow > 120, !token.isEmpty {
            return
        }

        let tokens = try await oauthService.refresh(
            clientID: clientID,
            clientSecret: clientSecret,
            refreshToken: refreshToken,
            baseURL: baseURL
        )
        try persist(tokens)
    }

    private func persist(_ tokens: FeishuOAuthTokens) throws {
        try tokenStore.write(tokens.accessToken)
        token = tokens.accessToken

        if let newRefreshToken = tokens.refreshToken, !newRefreshToken.isEmpty {
            try refreshTokenStore.write(newRefreshToken)
            refreshToken = newRefreshToken

            if let refreshTokenExpiresIn = tokens.refreshTokenExpiresIn,
               refreshTokenExpiresIn > 0 {
                refreshTokenExpiresAt = Date().addingTimeInterval(TimeInterval(refreshTokenExpiresIn))
                defaults.set(refreshTokenExpiresAt, forKey: Keys.refreshTokenExpiresAt)
            } else {
                refreshTokenExpiresAt = nil
                defaults.removeObject(forKey: Keys.refreshTokenExpiresAt)
            }
        } else {
            refreshTokenStore.delete()
            refreshToken = ""
            refreshTokenExpiresAt = nil
            defaults.removeObject(forKey: Keys.refreshTokenExpiresAt)
        }

        if tokens.expiresIn > 0 {
            accessTokenExpiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
            defaults.set(accessTokenExpiresAt, forKey: Keys.accessTokenExpiresAt)
        } else {
            accessTokenExpiresAt = nil
            defaults.removeObject(forKey: Keys.accessTokenExpiresAt)
        }
    }

    private func updateSelectedCalendarColor() {
        selectedCalendarColor = calendars.first(where: { $0.calendarID == calendarID })?.color
        if let selectedCalendarColor {
            defaults.set(selectedCalendarColor, forKey: Keys.selectedCalendarColor)
        } else {
            defaults.removeObject(forKey: Keys.selectedCalendarColor)
        }
    }

    private enum Keys {
        static let semesterStartDate = "semester-start-date"
        static let clientID = "feishu-client-id"
        static let calendarID = "calendarID"
        static let selectedCalendarColor = "feishu-selected-calendar-color"
        static let baseURL = "baseURL"
        static let accessTokenExpiresAt = "feishu-access-token-expires-at"
        static let refreshTokenExpiresAt = "feishu-refresh-token-expires-at"
    }
}

struct KeychainTokenStore: Sendable {
    private let service: String
    private let account: String

    init(service: String = "com.xiaodai.lark-widget", account: String) {
        self.service = service
        self.account = account
    }

    func read() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: errSecDecode)
        }
        return value
    }

    func write(_ value: String) throws {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let attributes: [CFString: Any] = [kSecValueData: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError(status: updateStatus)
        }
    }

    func delete() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        "Keychain error (\(status))."
    }
}
