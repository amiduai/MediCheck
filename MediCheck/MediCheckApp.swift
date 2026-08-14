import SwiftUI

@main
struct MediCheckApp: App {
    @StateObject private var storage: StorageService
    @StateObject private var service: ReminderService

    init() {
        let storage = StorageService()
        let service = ReminderService(storage: storage)
        _storage = StateObject(wrappedValue: storage)
        _service = StateObject(wrappedValue: service)
        // A hosted XCTest process also constructs the SwiftUI App. It must not
        // request notifications, open reminder windows, or register a login item.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            service.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(service: service, storage: storage)
        } label: {
            Image(systemName: "pill.fill")
                .accessibilityLabel("吃药提醒")
        }
        .menuBarExtraStyle(.window)

        Window("服药记录", id: "history") {
            HistoryView(storage: storage)
        }
        .defaultSize(width: 460, height: 600)

        Settings {
            SettingsView(service: service, storage: storage)
        }
    }
}
