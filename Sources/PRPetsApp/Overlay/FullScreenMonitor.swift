import AppKit
import PRPetsDesktop

/// Watches whether an app is full screen on the overlay's display. Checks on Space and app switches,
/// and once a second in case a window goes full screen without either.
@MainActor
final class FullScreenMonitor {
    private(set) var isFullScreen = false
    var onChange: ((Bool) -> Void)?
    private var screen: NSScreen?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    func start(watching screen: NSScreen) {
        self.screen = screen
        guard timer == nil else { return evaluate() }
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification].map { name in
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        evaluate()
    }

    private func evaluate() {
        guard let screen else { return }
        let fullScreen = FullScreenDetection.isFullScreen(
            display: screen.globalDisplayBounds,
            windows: Self.onScreenWindows(),
            ignoringProcess: ProcessInfo.processInfo.processIdentifier
        )
        guard fullScreen != isFullScreen else { return }
        isFullScreen = fullScreen
        Log.overlay.info("Full screen app \(fullScreen ? "appeared" : "left"); overlay \(fullScreen ? "hidden" : "shown")")
        onChange?(fullScreen)
    }

    /// Window bounds and layers are readable without Screen Recording permission; titles aren't needed.
    private static func onScreenWindows() -> [WindowSnapshot] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var ownerByProcessID: [Int32: WindowOwner] = [:]
        func owner(of pid: Int32) -> WindowOwner {
            if let known = ownerByProcessID[pid] { return known }
            let isOrdinaryApp = NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
            let owner: WindowOwner = isOrdinaryApp ? .app : .background
            ownerByProcessID[pid] = owner
            return owner
        }
        return info.compactMap { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else { return nil }
            return WindowSnapshot(ownerProcessID: pid, owner: owner(of: pid), layer: layer, bounds: bounds)
        }
    }
}

extension NSScreen {
    /// This screen in the window server's coordinates: origin at the top-left of the main display, y down.
    var globalDisplayBounds: CGRect {
        let mainHeight = NSScreen.screens.first?.frame.height ?? frame.height
        return CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
