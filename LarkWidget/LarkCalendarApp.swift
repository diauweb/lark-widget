import SwiftUI

@main
struct LarkCalendarApp: App {
    @StateObject private var store = LarkCalendarStore()

    var body: some Scene {
        Window("Feishu Calendar Settings", id: "settings") {
            LarkCalendarSettingsView(store: store)
        }
        .defaultSize(width: 560, height: 620)

        MenuBarExtra("Feishu Calendar", systemImage: "calendar.badge.clock") {
            LarkCalendarMenuBarView(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
