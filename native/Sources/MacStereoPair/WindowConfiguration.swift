import AppKit
import SwiftUI

enum MainWindowMetrics {
    static let minimumSize = NSSize(width: 1040, height: 660)
    static let defaultSize = minimumSize
    static let maximumSize = NSSize(width: 1240, height: 860)
    static let contentMaxWidth: CGFloat = 1120
}

enum WindowPlacementPolicy {
    static func requiresRecovery(
        windowFrame: CGRect,
        visibleFrame: CGRect
    ) -> Bool {
        let intersection = windowFrame.intersection(visibleFrame)
        return intersection.isNull ||
            intersection.width < 80 ||
            intersection.height < 80
    }
}

enum WindowSizePolicy {
    static func clamp(
        _ size: CGSize,
        minimum: CGSize,
        maximum: CGSize
    ) -> CGSize {
        CGSize(
            width: min(maximum.width, max(minimum.width, size.width)),
            height: min(maximum.height, max(minimum.height, size.height))
        )
    }
}

struct WindowConfigurator: NSViewRepresentable {
    let onVisibilityChanged: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        WindowConfigurationView(onVisibilityChanged: onVisibilityChanged)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? WindowConfigurationView else { return }
        view.onVisibilityChanged = onVisibilityChanged
        view.configureWindow()
    }
}

@MainActor
private final class WindowConfigurationView: NSView {
    var onVisibilityChanged: @MainActor (Bool) -> Void
    private var observers: [NSObjectProtocol] = []

    init(onVisibilityChanged: @escaping @MainActor (Bool) -> Void) {
        self.onVisibilityChanged = onVisibilityChanged
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        if let window {
            for notification in [
                NSWindow.didResizeNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
                NSWindow.didChangeOcclusionStateNotification
            ] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: notification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.enforceMaximumSize()
                        self.publishVisibility()
                    }
                })
            }
            for notification in [
                NSApplication.didHideNotification,
                NSApplication.didUnhideNotification
            ] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: notification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.publishVisibility()
                    }
                })
            }
        }
        configureWindow()
        publishVisibility()
    }

    func configureWindow() {
        guard let window else { return }
        window.contentMinSize = MainWindowMetrics.minimumSize
        window.contentMaxSize = MainWindowMetrics.maximumSize
        window.minSize = MainWindowMetrics.minimumSize
        window.maxSize = MainWindowMetrics.maximumSize
        window.isReleasedWhenClosed = false
        if let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame,
           WindowPlacementPolicy.requiresRecovery(
               windowFrame: window.frame,
               visibleFrame: visibleFrame
           ) {
            window.center()
        }
        enforceMaximumSize()
    }

    private func enforceMaximumSize() {
        guard let window else { return }
        let contentSize = window.contentRect(forFrameRect: window.frame).size
        let clamped = WindowSizePolicy.clamp(
            contentSize,
            minimum: MainWindowMetrics.minimumSize,
            maximum: MainWindowMetrics.maximumSize
        )
        guard clamped != contentSize else { return }
        window.setContentSize(clamped)
    }

    private func publishVisibility() {
        guard let window else {
            onVisibilityChanged(false)
            return
        }
        onVisibilityChanged(
            !NSApp.isHidden &&
                window.isVisible &&
                !window.isMiniaturized &&
                window.occlusionState.contains(.visible)
        )
    }

    isolated deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
