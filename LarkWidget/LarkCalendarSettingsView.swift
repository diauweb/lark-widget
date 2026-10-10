import SwiftUI
import ServiceManagement

struct LarkCalendarSettingsView: View {
    @ObservedObject var store: LarkCalendarStore
    @StateObject private var semesterDraft = SemesterSettingsDraft()
    @StateObject private var startup = StartupSettings()

    var body: some View {
        Form {
            Section {
                Text("Feishu Calendar")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Sign in once and the menu bar panel will keep your agenda available.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { startup.isRegistered },
                    set: { startup.setEnabled($0) }
                ))
                Text(startup.statusMessage)
                    .font(.caption)
                    .foregroundStyle(startup.requiresApproval ? .orange : .secondary)
                Button("Open Login Items Settings") {
                    SMAppService.openSystemSettingsLoginItems()
                }
                .buttonStyle(.bordered)
                if let errorMessage = startup.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }

            Section("Feishu OAuth app") {
                TextField("App ID (cli_…)", text: $store.clientID)
                SecureField("App secret", text: $store.clientSecret)
                Button("Sign in with Feishu", systemImage: "person.crop.circle.badge.checkmark") {
                    saveCalendarSettings()
                    store.signIn(clientID: store.clientID, clientSecret: store.clientSecret)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isAuthenticating)
                if store.isAuthenticating {
                    ProgressView("Waiting for Feishu…")
                }
                if let authMessage = store.authMessage {
                    Text(authMessage)
                        .font(.caption)
                        .foregroundStyle(authMessage.hasPrefix("Signed in") ? .green : .orange)
                        .textSelection(.enabled)
                }
            }

            Section("Calendar") {
                HStack {
                    Picker("Calendar", selection: Binding(
                        get: { store.calendarID },
                        set: { store.selectCalendar($0) }
                    )) {
                        if store.calendars.isEmpty {
                            Text("No calendars loaded").tag("")
                        } else {
                            ForEach(store.calendars) { calendar in
                                Text(calendar.displayName).tag(calendar.id)
                            }
                            if !store.calendarID.isEmpty && !store.calendars.contains(where: { $0.id == store.calendarID }) {
                                Text("Saved calendar unavailable").tag(store.calendarID)
                            }
                        }
                    }
                    .disabled(store.calendars.isEmpty || store.isLoadingCalendars)
                    Button {
                        store.loadCalendars()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(store.isLoadingCalendars || !store.isSignedIn)
                    .help("Refresh calendars")
                }
                if store.isLoadingCalendars {
                    ProgressView("Loading calendars…")
                } else if let calendarErrorMessage = store.calendarErrorMessage {
                    Text(calendarErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                } else if store.isSignedIn && store.calendars.isEmpty {
                    Text("No calendars are available for this Feishu account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextField("API base URL", text: $store.baseURL)
                HStack {
                    Button("Save calendar settings", systemImage: "checkmark") {
                        saveCalendarSettings()
                    }
                    .buttonStyle(.bordered)
                    if store.isSignedIn {
                        Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") {
                            store.signOut()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Section("School week") {
                DatePicker("Semester start", selection: $semesterDraft.startDate, displayedComponents: .date)
                Text("The Monday–Sunday week containing this date is Week 1.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Save semester start", systemImage: "checkmark") {
                    store.saveSemesterStartDate(semesterDraft.startDate)
                }
                .buttonStyle(.bordered)
                if let savedDate = store.semesterStartDate {
                    Text("Saved start: \(savedDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Set a start date to display school weeks in the calendar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Link("Open Feishu calendar API docs", destination: URL(string: "https://open.feishu.cn/document/server-docs/calendar-v4/calendar/list-2")!)
                Text("Access and refresh tokens are stored in macOS Keychain. The app refreshes the access token before it expires and saves Feishu's rotated refresh token.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .padding(.vertical, 12)
        .onAppear {
            startup.refresh()
            semesterDraft.startDate = store.semesterStartDate ?? .now
            store.loadCalendars()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            startup.refresh()
        }
    }

    private func saveCalendarSettings() {
        store.saveCalendarSettings(calendarID: store.calendarID, baseURL: store.baseURL)
    }
}

@MainActor
private final class StartupSettings: ObservableObject {
    @Published private var status = SMAppService.mainApp.status
    @Published private(set) var errorMessage: String?

    var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    var requiresApproval: Bool { status == .requiresApproval }

    var statusMessage: String {
        switch status {
        case .enabled:
            return "Feishu Calendar will open automatically when you log in."
        case .requiresApproval:
            return "Allow Feishu Calendar in macOS Login Items settings to finish enabling automatic startup."
        case .notRegistered:
            return "Feishu Calendar will not launch automatically at login."
        case .notFound:
            return "macOS could not find the app. Move it to Applications and try again."
        @unknown default:
            return "Check macOS Login Items settings for the current startup status."
        }
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        refresh()
        errorMessage = nil
        guard enabled != isRegistered else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = "Could not change automatic startup: \(error.localizedDescription)"
        }
        refresh()
    }
}

@MainActor
private final class SemesterSettingsDraft: ObservableObject {
    @Published var startDate = Date.now
}
