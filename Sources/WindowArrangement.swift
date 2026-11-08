import AppKit
import ApplicationServices

struct SharedWindowTarget {
    let processID: pid_t
    let title: String
    /// ScreenCaptureKit / Accessibility coordinates: origin at the primary display's top-left.
    let frame: CGRect
}

enum WindowArrangement {
    enum Failure: LocalizedError {
        case permissionRequired
        case windowAccess(AXError)

        var errorDescription: String? {
            switch self {
            case .permissionRequired:
                return "macOS has not authorized this copy of StudySide. If its Accessibility switch is already on, turn it off and on again. If that does not help, remove the old entry with the minus button and add the StudySide app you are currently running. Then quit and reopen StudySide. This one-time migration is needed when upgrading from an older temporary signature; future builds signed with the same certificate retain the app identity. Screen sharing is already selected."
            case .windowAccess(let code):
                return "Accessibility is enabled, but the course app did not provide its windows (error \(code.rawValue)). Keep the course app open, exit full screen or presentation mode, and select its window again."
            }
        }
    }

    static func windowAccessFailure(_ code: AXError, isTrusted: Bool) -> Failure {
        isTrusted ? .windowAccess(code) : .permissionRequired
    }

    struct Frames {
        let course: CGRect
        let assistant: CGRect
    }

    static func frames(in visibleFrame: CGRect) throws -> Frames {
        let bounds = visibleFrame.insetBy(dx: 8, dy: 8)
        let gap: CGFloat = 12
        let assistantWidth = max(390, min(450, floor(bounds.width * 0.30)))
        let courseWidth = bounds.width - assistantWidth - gap
        guard courseWidth >= 500, bounds.height >= 620 else {
            throw AppError.message("There is not enough space on this display for both windows. Hide the Dock or use a larger display, then try again.")
        }
        return Frames(course: CGRect(x: bounds.minX, y: bounds.minY, width: courseWidth, height: bounds.height),
                      assistant: CGRect(x: bounds.maxX - assistantWidth, y: bounds.minY, width: assistantWidth, height: bounds.height))
    }

    static func axFrame(from appKitFrame: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: appKitFrame.minX, y: primaryTop - appKitFrame.maxY, width: appKitFrame.width, height: appKitFrame.height)
    }

    static func appKitFrame(from axFrame: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: axFrame.minX, y: primaryTop - axFrame.maxY, width: axFrame.width, height: axFrame.height)
    }

    static func trusted(prompt: Bool) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        return AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }

    private static func rect(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute), let size = value(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private static func close(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 4) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance &&
        abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    private static func matchingWindow(_ target: SharedWindowTarget) throws -> AXUIElement {
        let application = AXUIElementCreateApplication(target.processID)
        AXUIElementSetMessagingTimeout(application, 2)
        var result: CFTypeRef?
        let code = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &result)
        guard code == .success, let windows = result as? [AXUIElement] else {
            throw windowAccessFailure(code, isTrusted: trusted(prompt: false))
        }
        let titled = target.title.isEmpty ? [] : windows.filter { value($0, kAXTitleAttribute) as? String == target.title }
        if titled.count == 1 { return titled[0] }
        let candidates = titled.isEmpty ? windows : titled
        let geometrical = candidates.filter { window in rect(window).map { close($0, target.frame, tolerance: 12) } ?? false }
        guard geometrical.count == 1 else {
            throw AppError.message("Could not uniquely identify the shared window. Select it again, then arrange the windows.")
        }
        return geometrical[0]
    }

    private static func apply(_ frame: CGRect, to element: AXUIElement) throws {
        var point = frame.origin, size = frame.size
        var movable = DarwinBoolean(false), resizable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &movable) == .success, movable.boolValue,
              AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &resizable) == .success, resizable.boolValue,
              let pointValue = AXValueCreate(.cgPoint, &point), let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw AppError.message("This window cannot be moved or resized. Exit full screen, presentation, or locked reading mode, then try again.")
        }
        // Position twice because some applications clamp the first move at their previous size.
        _ = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, pointValue)
        guard AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue) == .success,
              AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, pointValue) == .success else {
            throw AppError.message("The course app did not accept the new window size. Exit full screen or presentation mode, then try again.")
        }
    }

    @MainActor static func arrange(target: SharedWindowTarget, assistant: NSWindow) async throws {
        guard trusted(prompt: true) else {
            throw Failure.permissionRequired
        }
        guard !assistant.styleMask.contains(.fullScreen) else {
            throw AppError.message("Exit StudySide's full-screen mode, then click Arrange Again.")
        }
        let element = try matchingWindow(target)
        if value(element, "AXFullScreen") as? Bool == true {
            throw AppError.message("The course window is in full screen. Exit full screen or presentation mode, then click Arrange Again.")
        }
        guard let originalCourse = rect(element), let primary = NSScreen.screens.first else {
            throw AppError.message("Could not read the course window's position. Select the window again.")
        }
        let primaryTop = primary.frame.maxY
        let courseOnDesktop = appKitFrame(from: originalCourse, primaryTop: primaryTop)
        let screen = NSScreen.screens.max {
            let l = $0.frame.intersection(courseOnDesktop)
            let r = $1.frame.intersection(courseOnDesktop)
            return (l.isNull ? 0 : l.width * l.height) < (r.isNull ? 0 : r.width * r.height)
        } ?? assistant.screen ?? primary
        let arrangement = try frames(in: screen.visibleFrame)
        let expectedCourse = axFrame(from: arrangement.course, primaryTop: primaryTop)
        let originalAssistant = assistant.frame
        do {
            try apply(expectedCourse, to: element)
            try await Task.sleep(for: .milliseconds(180))
            try Task.checkCancellation()
            guard let actual = rect(element), close(actual, expectedCourse, tolerance: 12) else {
                throw AppError.message("The course app's minimum window size prevents a side-by-side layout. Reduce its UI scale or use a larger display.")
            }
            assistant.setFrame(arrangement.assistant, display: true, animate: false)
            guard close(assistant.frame, arrangement.assistant, tolerance: 3) else {
                assistant.setFrame(originalAssistant, display: true)
                throw AppError.message("StudySide could not fit into the space on the right. Please try again.")
            }
            // Keep the companion eligible to appear alongside another app in Stage Manager.
            // This is independent of the user's pin choice and does not make it always-on-top.
            var behavior = assistant.collectionBehavior
            behavior.subtract([.primary, .auxiliary, .canJoinAllSpaces])
            behavior.insert([.canJoinAllApplications, .moveToActiveSpace])
            assistant.collectionBehavior = behavior
            _ = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
            _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            NSRunningApplication(processIdentifier: target.processID)?.activate(options: [])
            NSApp.activate(ignoringOtherApps: true)
            assistant.makeKeyAndOrderFront(nil)
        } catch {
            try? apply(originalCourse, to: element)
            throw error
        }
    }

    @MainActor static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
