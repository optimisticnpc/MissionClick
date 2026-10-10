import AppKit

func entry(_ id: UInt32, _ pid: Int32, _ layer: Int, _ frame: CGRect, alpha: Double = 1) -> [String: Any] {
    [kCGWindowNumber as String: NSNumber(value: id),
     kCGWindowOwnerPID as String: NSNumber(value: pid),
     kCGWindowLayer as String: NSNumber(value: layer),
     kCGWindowAlpha as String: NSNumber(value: alpha),
     kCGWindowBounds as String: ["X": frame.minX, "Y": frame.minY, "Width": frame.width, "Height": frame.height]]
}

@main struct SelectionTests {
    static func main() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 120)
        let surface = entry(10, 42, 18, frame)
        let top = entry(11, 60, 0, frame)
        let underneath = entry(12, 60, 0, frame)
        let point = CGPoint(x: 180, y: 150)
        assert(WindowSelection.missionControlIsVisible([surface], dockPID: 42))
        assert(!WindowSelection.missionControlIsVisible([surface], dockPID: 41))
        assert(!WindowSelection.missionControlIsVisible([surface], dockPID: nil))
        assert(!WindowSelection.missionControlIsVisible([top], dockPID: 60))
        assert(!WindowSelection.missionControlIsVisible([entry(13, 42, 20, frame)], dockPID: 42))
        let selected = WindowSelection.target(at: point, entries: [surface, top, underneath], excludedPIDs: [42])
        assert(selected?.id == 11 && selected?.pid == 60)
        assert(WindowSelection.target(at: point, entries: [top], excludedPIDs: [60]) == nil)
        assert(WindowSelection.target(at: .zero, entries: [top], excludedPIDs: []) == nil)
        assert(WindowSelection.target(at: point, entries: [entry(0, 60, 0, frame)], excludedPIDs: []) == nil)
        assert(WindowSelection.target(at: point, entries: [entry(13, 60, 0, frame, alpha: 0)], excludedPIDs: []) == nil)
        assert(WindowSelection.target(at: point, entries: [[kCGWindowLayer as String: 0]], excludedPIDs: []) == nil)
        let leftScreen = CGRect(x: -800, y: -100, width: 200, height: 120)
        assert(WindowSelection.target(at: CGPoint(x: -750, y: -50), entries: [entry(15, 61, 0, leftScreen)], excludedPIDs: [])?.id == 15)
        assert(WindowSelection.target(at: point, entries: [entry(16, 61, 0, CGRect(x: 180, y: 150, width: 0, height: 0))], excludedPIDs: []) == nil)
        print("13 window-selection checks passed.")
    }
}
