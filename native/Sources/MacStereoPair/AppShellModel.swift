import Combine

@MainActor
final class AppShellModel: ObservableObject {
    let console = ConsoleViewModel()
}
