import AppKit
import ScreenCaptureKit

/// A shareable window, flattened into a Sendable value so SCWindow never
/// crosses an actor boundary.
struct WindowInfo: Identifiable, Hashable, Sendable {
    let id: CGWindowID
    let app: String
    let title: String
    let frame: CGRect
}

/// Window listing + crisp single-window screenshots via ScreenCaptureKit.
/// Requires the Screen Recording permission; macOS applies a fresh grant on
/// the app's next launch.
enum WindowCapture {

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    static func openSystemSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// On-screen, normal-level windows of other apps, sorted by app name.
    static func listWindows() async -> [WindowInfo] {
        guard let content = try? await SCShareableContent
            .excludingDesktopWindows(true, onScreenWindowsOnly: true)
        else { return [] }
        let myPID = ProcessInfo.processInfo.processIdentifier
        return content.windows.compactMap { w -> WindowInfo? in
            guard w.windowLayer == 0,
                  w.frame.width >= 100, w.frame.height >= 80,
                  w.isOnScreen,
                  let app = w.owningApplication,
                  app.processID != myPID
            else { return nil }
            return WindowInfo(id: w.windowID,
                              app: app.applicationName.isEmpty ? "App" : app.applicationName,
                              title: w.title ?? "",
                              frame: w.frame)
        }
        .sorted { ($0.app.lowercased(), $0.title.lowercased()) < ($1.app.lowercased(), $1.title.lowercased()) }
    }

    /// Screenshot of a single window at 2x scale, no shadow, transparent
    /// background (so native rounded corners stay transparent — we composite
    /// our own shadow later).
    static func capture(windowID: CGWindowID) async -> CGImage? {
        guard let content = try? await SCShareableContent
            .excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let win = content.windows.first(where: { $0.windowID == windowID })
        else { return nil }

        let filter = SCContentFilter(desktopIndependentWindow: win)
        let config = SCStreamConfiguration()
        config.width = max(2, Int(win.frame.width) * 2)
        config.height = max(2, Int(win.frame.height) * 2)
        config.showsCursor = false
        config.captureResolution = .best
        config.ignoreShadowsSingleWindow = true
        config.backgroundColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
        return try? await SCScreenshotManager.captureImage(contentFilter: filter,
                                                           configuration: config)
    }
}
