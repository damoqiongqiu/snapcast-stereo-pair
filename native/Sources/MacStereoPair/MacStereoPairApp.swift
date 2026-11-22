import SwiftUI

@main
struct MacStereoPairApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = ConsoleViewModel()
    @StateObject private var language = AppLanguage()
    @StateObject private var notifications = NotificationManager()

    var body: some Scene {
        Window("MacBook Stereo Pair", id: "console") {
            AppRootView(model: model, notifications: notifications)
                .environmentObject(language)
                .environmentObject(notifications)
                .environment(\.locale, language.locale)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(
            width: MainWindowMetrics.defaultSize.width,
            height: MainWindowMetrics.defaultSize.height
        )
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("MacBook Stereo Pair", systemImage: "hifispeaker.2.fill") {
            MenuBarContent(model: model)
                .environmentObject(language)
                .environment(\.locale, language.locale)
        }
        .menuBarExtraStyle(.menu)
    }
}
