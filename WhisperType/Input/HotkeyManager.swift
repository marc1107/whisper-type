import Cocoa
import Carbon.HIToolbox

final class HotkeyManager {
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?

    private let settings = AppSettings.shared
    private var isHotkeyPressed = false

    func start() throws {
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw HotkeyError.tapCreationFailed
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    fileprivate func handleEvent(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        let targetKeyCode = Int64(settings.hotkeyKeyCode)
        let targetModifiers = CGEventFlags(rawValue: UInt64(settings.hotkeyModifiers))

        let relevantFlags: CGEventFlags = [.maskAlternate, .maskControl, .maskCommand, .maskShift]
        let currentRelevant = flags.intersection(relevantFlags)
        let targetRelevant = targetModifiers.intersection(relevantFlags)

        guard currentRelevant == targetRelevant && keyCode == targetKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown && !isHotkeyPressed {
            isHotkeyPressed = true
            DispatchQueue.main.async { [weak self] in
                self?.onHotkeyDown?()
            }
            return nil // Swallow the event
        } else if type == .keyUp && isHotkeyPressed {
            isHotkeyPressed = false
            if settings.hotkeyMode == .pushToTalk {
                DispatchQueue.main.async { [weak self] in
                    self?.onHotkeyUp?()
                }
            }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    deinit {
        stop()
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo = userInfo {
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    return manager.handleEvent(type, event: event)
}

enum HotkeyError: LocalizedError {
    case tapCreationFailed

    var errorDescription: String? {
        switch self {
        case .tapCreationFailed:
            return "Globaler Hotkey konnte nicht registriert werden. Bitte Bedienungshilfen-Berechtigung prüfen."
        }
    }
}
