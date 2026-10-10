import AppKit
import SwiftUI

enum MenuBarWindowPlacement {
    /// Move the frame into the usable screen area without changing its size.
    static func origin(for frame: CGRect, in visibleFrame: CGRect) -> CGPoint {
        let bounds = visibleFrame.insetBy(dx: 8, dy: 8)
        return CGPoint(
            x: max(bounds.minX, min(frame.minX, bounds.maxX - frame.width)),
            // On a display smaller than the panel, keep its top controls reachable.
            y: min(bounds.maxY - frame.height, max(frame.minY, bounds.minY))
        )
    }
}

/// Keep SwiftUI's menu-bar window on the display where it was opened.
/// SwiftUI still owns presentation, dismissal, and the initial button anchoring.
struct MenuBarWindowPositioner: NSViewRepresentable {
    func makeNSView(context: Context) -> PositioningView { PositioningView() }

    func updateNSView(_ nsView: PositioningView, context: Context) {
        nsView.scheduleCorrection()
    }

    final class PositioningView: NSView {
        private var presentationScreen: NSScreen?
        private var correctionScheduled = false

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            NotificationCenter.default.removeObserver(self)
            presentationScreen = nil
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(windowOpened),
                               name: NSWindow.didBecomeKeyNotification, object: window)
            center.addObserver(self, selector: #selector(visibilityChanged),
                               name: NSWindow.didChangeOcclusionStateNotification, object: window)
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                         NSWindow.didChangeScreenNotification] {
                center.addObserver(self, selector: #selector(geometryChanged), name: name, object: window)
            }
            center.addObserver(self, selector: #selector(screensChanged),
                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
            capturePresentationScreen()
            scheduleCorrection()
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        @objc private func windowOpened(_ notification: Notification) {
            capturePresentationScreen()
            scheduleCorrection()
        }

        private func capturePresentationScreen() {
            // Capture the clicked display before correcting an overflowing frame:
            // window.screen alone can identify the neighboring display it spills onto.
            let mouse = NSEvent.mouseLocation
            presentationScreen = NSScreen.screens.first { screen in
                screen.frame.contains(mouse) && mouse.y >= screen.visibleFrame.maxY
            } ?? window?.screen
        }

        @objc private func visibilityChanged(_ notification: Notification) {
            if window?.isVisible != true {
                presentationScreen = nil
            } else {
                if presentationScreen == nil { capturePresentationScreen() }
                scheduleCorrection()
            }
        }

        @objc private func geometryChanged(_ notification: Notification) {
            scheduleCorrection()
        }

        @objc private func screensChanged(_ notification: Notification) {
            presentationScreen = nil
            scheduleCorrection()
        }

        func scheduleCorrection() {
            guard !correctionScheduled else { return }
            correctionScheduled = true
            // Let SwiftUI finish its current positioning/layout pass first.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.correctionScheduled = false
                self.correctPosition()
            }
        }

        private func correctPosition() {
            guard let window, window.isVisible,
                  let screen = presentationScreen ?? window.screen else { return }
            let origin = MenuBarWindowPlacement.origin(for: window.frame, in: screen.visibleFrame)
            // setFrameOrigin emits didMove; this check makes that follow-up a no-op.
            guard abs(window.frame.minX - origin.x) > 0.5 ||
                  abs(window.frame.minY - origin.y) > 0.5 else { return }
            window.setFrameOrigin(origin)
        }
    }
}
