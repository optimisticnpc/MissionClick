import AppKit
import ApplicationServices
import Darwin
import ServiceManagement

enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var statusText: String {
        switch status {
        case .enabled: return "enabled"
        case .requiresApproval: return "requires approval"
        case .notRegistered: return "disabled"
        case .notFound: return "unavailable"
        @unknown default: return "unknown"
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        switch (enabled, status) {
        case (true, .enabled), (true, .requiresApproval), (false, .notRegistered): return
        case (true, _): try SMAppService.mainApp.register()
        case (false, _): try SMAppService.mainApp.unregister()
        }
    }
}

// This is the sole private API: resolve a real AX window's CGWindowID. No title
// matching, key injection, force quit, screen capture, or simulated app activation.
typealias WindowIDFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
let windowIDFunction: WindowIDFunction? = {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
    return unsafeBitCast(symbol, to: WindowIDFunction.self)
}()

func windowEntries() -> [[String: Any]] {
    CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
}

func dockPID() -> pid_t? {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func closeWindow(_ target: WindowTarget) -> String {
    guard AXIsProcessTrusted(), let resolveID = windowIDFunction else { return "Accessibility access is required." }
    let app = AXUIElementCreateApplication(target.pid)
    AXUIElementSetMessagingTimeout(app, 0.35)
    guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else {
        return "The app did not expose its windows."
    }
    for window in windows {
        AXUIElementSetMessagingTimeout(window, 0.35)
        var id: CGWindowID = 0
        guard resolveID(window, &id) == .success, id == target.id else { continue }
        // Do not act on full-screen Spaces, sheets, or disabled close controls.
        if attribute(window, "AXFullScreen") as? Bool == true { return "Full-screen Spaces are not supported." }
        guard let raw = attribute(window, kAXCloseButtonAttribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            return "This window has no accessible close button."
        }
        let button = raw as! AXUIElement
        AXUIElementSetMessagingTimeout(button, 0.35)
        guard attribute(button, kAXEnabledAttribute) as? Bool == true else {
            return "This window's close button is disabled."
        }
        // Check again immediately before the only mutation. Do not close a stale
        // target after the user has already left Mission Control.
        guard WindowSelection.missionControlIsVisible(windowEntries(), dockPID: dockPID()) else {
            return "Mission Control was closed; no action taken."
        }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
            ? "Window close requested." : "The app could not close that window."
    }
    return "The selected window is no longer available."
}

final class MissionClick: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var statusLine: NSMenuItem!
    var enabledItem: NSMenuItem!
    var loginItem: NSMenuItem!
    var resultItem: NSMenuItem!
    var tap: CFMachPort?
    var source: CFRunLoopSource?
    var permissionTimer: Timer?
    var setupWindow: NSWindow?
    var enabled = true
    var swallowMouseUp = false
    var busy = false
    var lastResult = "No windows closed yet."
    let worker = DispatchQueue(label: "local.missionclick.close")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.35)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: "MissionClick")
        statusItem.button?.toolTip = "MissionClick — right-click to close in Mission Control"
        menu = NSMenu()
        menu.delegate = self
        let title = menu.addItem(withTitle: "MissionClick", action: nil, keyEquivalent: "")
        title.isEnabled = false
        statusLine = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        enabledItem = addItem("Enable right-click to close", action: #selector(toggleEnabled))
        loginItem = addItem("Launch at login", action: #selector(toggleLaunchAtLogin))
        addItem("Setup & instructions…", action: #selector(showSetup))
        addItem("Open Accessibility Settings…", action: #selector(openAccessibility))
        resultItem = menu.addItem(withTitle: lastResult, action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        addItem("Quit MissionClick", action: #selector(quit))
        statusItem.menu = menu
        reconcilePermission()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.reconcilePermission() }
        RunLoop.main.add(permissionTimer!, forMode: .common)
        if !AXIsProcessTrusted() { showSetup() }
    }

    @discardableResult func addItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) { refreshMenu() }

    func refreshMenu() {
        statusLine.title = windowIDFunction == nil ? "Unsupported macOS interface" :
            (!AXIsProcessTrusted() ? "Waiting for Accessibility access" : (tap == nil ? "Unable to monitor clicks" : "Ready"))
        enabledItem.state = enabled ? .on : .off
        switch LoginItem.status {
        case .enabled:
            loginItem.title = "Launch at login"
            loginItem.state = .on
        case .requiresApproval:
            loginItem.title = "Launch at login (approval required)"
            loginItem.state = .mixed
        default:
            loginItem.title = "Launch at login"
            loginItem.state = .off
        }
        resultItem.title = lastResult
    }

    func reconcilePermission() {
        if AXIsProcessTrusted(), windowIDFunction != nil {
            if tap == nil { installTap() }
        } else if tap != nil { removeTap() }
        refreshMenu()
    }

    func installTap() {
        let mask = CGEventMask(1 << CGEventType.rightMouseDown.rawValue) |
                   CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<MissionClick>.fromOpaque(context).takeUnretainedValue()
                return controller.handle(type, event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        tap = created
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
    }

    func removeTap() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        swallowMouseUp = false
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            swallowMouseUp = false
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .rightMouseUp, swallowMouseUp {
            swallowMouseUp = false
            return nil
        }
        // Modifier-right-clicks pass through so existing gestures keep working.
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        guard type == .rightMouseDown, enabled, AXIsProcessTrusted(),
              event.flags.intersection(modifiers).isEmpty, let dock = dockPID() else {
            return Unmanaged.passUnretained(event)
        }
        let entries = windowEntries()
        guard WindowSelection.missionControlIsVisible(entries, dockPID: dock) else {
            return Unmanaged.passUnretained(event)
        }
        var excluded: Set<pid_t> = [dock, getpid()]
        for id in ["com.apple.WindowManager", "com.apple.controlcenter", "com.apple.notificationcenterui"] {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: id) { excluded.insert(app.processIdentifier) }
        }
        guard let target = WindowSelection.target(at: event.location, entries: entries, excludedPIDs: excluded) else {
            return Unmanaged.passUnretained(event)
        }
        swallowMouseUp = true
        guard !busy else { return nil }
        busy = true
        let point = event.location
        worker.async { [weak self] in
            // Avoid choosing a different window during Mission Control's reflow.
            let fresh = windowEntries()
            let same = WindowSelection.target(at: point, entries: fresh, excludedPIDs: excluded)
            let result: String
            if same?.id == target.id, same?.pid == target.pid,
               WindowSelection.missionControlIsVisible(fresh, dockPID: dock) {
                result = closeWindow(target)
            } else { result = "The previews moved; please right-click again." }
            DispatchQueue.main.async {
                self?.busy = false
                self?.lastResult = result
                self?.refreshMenu()
            }
        }
        return nil
    }

    @objc func toggleEnabled() { enabled.toggle(); refreshMenu() }
    @objc func toggleLaunchAtLogin() {
        let enable = LoginItem.status != .enabled && LoginItem.status != .requiresApproval
        do {
            try LoginItem.setEnabled(enable)
            lastResult = "Launch at login: \(LoginItem.statusText)."
            if LoginItem.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            lastResult = "Could not change launch at login."
            let alert = NSAlert()
            alert.messageText = "Could not change launch at login"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Open Login Items Settings")
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
        refreshMenu()
    }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func openAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func showSetup() {
        if let setupWindow { setupWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "MissionClick"
        window.isReleasedWhenClosed = false
        let heading = NSTextField(labelWithString: "Right-click. Close window.")
        heading.font = .systemFont(ofSize: 24, weight: .semibold)
        heading.frame = NSRect(x: 28, y: 256, width: 404, height: 34)
        let text = NSTextField(wrappingLabelWithString:
            "1. Enable MissionClick in Accessibility Settings.\n\n2. Open Mission Control as usual.\n\n3. Right-click a window preview to close it.\n\nMissionClick stays in your menu bar. Unsaved changes still use the app’s normal save prompt.")
        text.font = .systemFont(ofSize: 14)
        text.frame = NSRect(x: 28, y: 70, width: 404, height: 170)
        let button = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openAccessibility))
        button.bezelStyle = .rounded
        button.frame = NSRect(x: 24, y: 22, width: 240, height: 32)
        window.contentView?.addSubview(heading)
        window.contentView?.addSubview(text)
        window.contentView?.addSubview(button)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        setupWindow = window
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        removeTap()
    }
}

if CommandLine.arguments.contains("--diagnose") {
    print("Accessibility: \(AXIsProcessTrusted())")
    print("Window ID interface: \(windowIDFunction != nil)")
    print("Mission Control detected: \(WindowSelection.missionControlIsVisible(windowEntries(), dockPID: dockPID()))")
    print("Launch at login: \(LoginItem.statusText)")
    exit(0)
}

if CommandLine.arguments.contains("--login-status") {
    print("Launch at login: \(LoginItem.statusText)")
    exit(0)
}

if CommandLine.arguments.contains("--enable-login") || CommandLine.arguments.contains("--disable-login") {
    do {
        try LoginItem.setEnabled(CommandLine.arguments.contains("--enable-login"))
        print("Launch at login: \(LoginItem.statusText)")
        exit(LoginItem.status == .requiresApproval ? 2 : 0)
    } catch {
        fputs("Could not change launch at login: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

// Launch Services can find several builds with the same bundle identifier.
// Only one copy should install an event tap, even if a second app is opened.
if let identifier = Bundle.main.bundleIdentifier,
   let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
    .first(where: { $0.processIdentifier != getpid() && !$0.isTerminated }) {
    existing.activate(options: [])
    exit(0)
}

let application = NSApplication.shared
let delegate = MissionClick()
application.delegate = delegate
application.run()
