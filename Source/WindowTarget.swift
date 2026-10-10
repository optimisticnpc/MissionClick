import AppKit
import CoreGraphics

struct WindowTarget: Equatable {
    let id: CGWindowID
    let pid: pid_t
    let frame: CGRect
}

enum WindowSelection {
    // On macOS 14–26, the Dock's layer-18 surface identifies Mission Control.
    // Treat unknown system layouts as inactive rather than intercepting clicks.
    static func missionControlIsVisible(_ entries: [[String: Any]], dockPID: pid_t?) -> Bool {
        guard let dockPID else { return false }
        return entries.contains {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == dockPID &&
            ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 18
        }
    }

    static func target(at point: CGPoint, entries: [[String: Any]],
                       excludedPIDs: Set<pid_t>) -> WindowTarget? {
        // CGWindowList returns front-to-back order and transformed preview bounds.
        for entry in entries {
            guard (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  !excludedPIDs.contains(pid),
                  let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  id != 0,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? NSNumber, let y = bounds["Y"] as? NSNumber,
                  let width = bounds["Width"] as? NSNumber, let height = bounds["Height"] as? NSNumber
            else { continue }
            let frame = CGRect(x: x.doubleValue, y: y.doubleValue,
                               width: width.doubleValue, height: height.doubleValue)
            guard frame.width > 1, frame.height > 1, !frame.isInfinite, !frame.isNull,
                  frame.contains(point) else { continue }
            if let alpha = entry[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue <= 0 { continue }
            return WindowTarget(id: id, pid: pid, frame: frame)
        }
        return nil
    }
}
