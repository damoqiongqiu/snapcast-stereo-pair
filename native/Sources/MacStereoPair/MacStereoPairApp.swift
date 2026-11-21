import SwiftUI

@main
struct MacStereoPairApp: App {
    @StateObject private var model = ConsoleViewModel()
    @StateObject private var language = AppLanguage()
    @StateObject private var notifications = NotificationManager()

    var body: some Scene {
        WindowGroup("MacBook Stereo Pair", id: "console") {
            AppRootView(model: model, notifications: notifications)
                .environmentObject(language)
                .environmentObject(notifications)
                .environment(\.locale, language.locale)
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("MacBook Stereo Pair", systemImage: "hifispeaker.2.fill") {
            MenuBarContent(model: model)
                .environmentObject(language)
                .environment(\.locale, language.locale)
        }
        .menuBarExtraStyle(.menu)
    }
}
