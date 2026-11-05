import CoreGraphics

/// What kind of process owns a window.
public enum WindowOwner: Hashable, Sendable {
    /// An ordinary app with a Dock icon: browsers, editors, Keynote.
    case app
    /// Background and system processes: the Dock, notifications, Control Center, Stage Manager.
    case background
}

/// One on-screen window, as the window server reports it. Bounds use global display coordinates
/// with the origin at the top-left of the main display.
public struct WindowSnapshot: Hashable, Sendable {
    public let ownerProcessID: Int32
    public let owner: WindowOwner
    public let layer: Int
    public let bounds: CGRect

    public init(ownerProcessID: Int32, owner: WindowOwner, layer: Int, bounds: CGRect) {
        self.ownerProcessID = ownerProcessID
        self.owner = owner
        self.layer = layer
        self.bounds = bounds
    }
}

/// Decides whether some app is full screen (or presenting) on a display.
///
/// A full-screen window covers the whole display, menu bar strip included; a maximised window stops below
/// the menu bar. Only windows belonging to ordinary apps count. The Dock in particular keeps a window the size
/// of the display, which comes on screen whenever it slides out, and notifications and Mission Control do the same.
public enum FullScreenDetection {
    /// Window server layers ordinary apps and slideshows draw at. Menu bar and above are system chrome.
    static let appLayers = 0..<24
    /// Retina rounding can leave a window a fraction of a point short of the display.
    static let tolerance: CGFloat = 1

    public static func isFullScreen(display: CGRect, windows: [WindowSnapshot], ignoringProcess ownProcessID: Int32) -> Bool {
        windows.contains { window in
            window.ownerProcessID != ownProcessID
                && window.owner == .app
                && appLayers.contains(window.layer)
                && covers(window.bounds, display)
        }
    }

    private static func covers(_ bounds: CGRect, _ display: CGRect) -> Bool {
        bounds.minX <= display.minX + tolerance
            && bounds.minY <= display.minY + tolerance
            && bounds.maxX >= display.maxX - tolerance
            && bounds.maxY >= display.maxY - tolerance
    }
}
