import SwiftUI

struct AppRootView: View {
    @ObservedObject var model: ConsoleViewModel
    @ObservedObject var notifications: NotificationManager
    @StateObject private var setup = SetupViewModel()

    var body: some View {
        Group {
            if setup.flow.isConsoleEnabled {
                ConsoleView(model: model)
            } else {
                SetupFlowView(setup: setup, model: model)
            }
        }
        .background(WindowConfigurator())
        .task {
            await model.start()
            await setup.start()
        }
    }
}
