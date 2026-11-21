import SwiftUI

@main
struct MacStereoPairApp: App {
    @StateObject private var model = ConsoleViewModel()

    var body: some Scene {
        WindowGroup("MacBook Stereo Pair", id: "console") {
            ConsoleView(model: model)
                .task { await model.start() }
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("MacBook Stereo Pair", systemImage: "hifispeaker.2.fill") {
            MenuBarContent(model: model)
        }
        .menuBarExtraStyle(.menu)
    }
}
