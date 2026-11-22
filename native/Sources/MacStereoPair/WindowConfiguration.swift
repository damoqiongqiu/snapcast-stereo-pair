import AppKit
import SwiftUI

enum MainWindowMetrics {
    static let minimumSize = NSSize(width: 900, height: 680)
    static let defaultSize = NSSize(width: 1040, height: 720)
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
    func makeNSView(context: Context) -> NSView {
        WindowConfigurationView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowConfigurationView)?.configureWindow()
    }
}

@MainActor
private final class WindowConfigurationView: NSView {
    private var resizeObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
            self.resizeObserver = nil
        }
        if let window {
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.enforceMaximumSize()
                }
            }
        }
        configureWindow()
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

    isolated deinit {
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
        }
    }
}
