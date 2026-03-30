import Carbon.HIToolbox
import Cocoa
import SwiftUI

struct HotkeyRecorderView: View {
    @ObservedObject var settings: AppSettings
    @State private var isRecording = false
    @State private var displayText = ""
    @State private var pendingKeyCode: Int = -1
    @State private var pendingModifiers: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isRecording ? (displayText.isEmpty ? "Drücke Tastenkombination..." : displayText) : settings.hotkeyDisplayString)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(isRecording ? .accentColor : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isRecording ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isRecording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
                    )

                if isRecording {
                    Button("Abbrechen") {
                        stopRecording(save: false)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Ändern") {
                        startRecording()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if isRecording {
                Text("Drücke die gewünschte Tastenkombination. Nur Modifier-Tasten (Fn, Control, Option, Shift, Command) oder Modifier + Taste.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .background(
            HotkeyRecorderNSView(
                isRecording: $isRecording,
                displayText: $displayText,
                pendingKeyCode: $pendingKeyCode,
                pendingModifiers: $pendingModifiers,
                onConfirm: { stopRecording(save: true) }
            )
            .frame(width: 0, height: 0)
        )
    }

    private func startRecording() {
        displayText = ""
        pendingKeyCode = -1
        pendingModifiers = 0
        isRecording = true
    }

    private func stopRecording(save: Bool) {
        isRecording = false
        if save && pendingModifiers != 0 {
            settings.hotkeyKeyCode = pendingKeyCode
            settings.hotkeyModifiers = pendingModifiers
        }
        displayText = ""
    }
}

// NSView-based key event monitor that captures key combos when recording
struct HotkeyRecorderNSView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var displayText: String
    @Binding var pendingKeyCode: Int
    @Binding var pendingModifiers: Int
    let onConfirm: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = RecorderView()
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        let wasRecording = context.coordinator.isRecording
        context.coordinator.isRecording = isRecording
        if wasRecording != isRecording {
            context.coordinator.update()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator {
        var parent: HotkeyRecorderNSView
        var isRecording = false
        var localMonitor: Any?
        var flagsMonitor: Any?
        private var confirmTimer: Timer?
        // Track the peak (most modifiers held at once) so releasing one key
        // slightly before another doesn't lose the combination.
        private var peakModifiers: Int = 0
        private var peakKeyCode: Int = -1

        init(parent: HotkeyRecorderNSView) {
            self.parent = parent
        }

        func startMonitoring() {
            stopMonitoring()
            peakModifiers = 0
            peakKeyCode = -1

            // Monitor key events
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self, self.isRecording else { return event }

                let flags = event.modifierFlags
                let keyCode = event.keyCode
                let modRaw = self.modifierFlagsToRaw(flags)

                if modRaw != 0 {
                    self.peakKeyCode = Int(keyCode)
                    self.peakModifiers = modRaw
                    self.parent.pendingKeyCode = self.peakKeyCode
                    self.parent.pendingModifiers = self.peakModifiers
                    self.parent.displayText = self.buildDisplayString(modifiers: modRaw, keyCode: Int(keyCode))
                    self.scheduleConfirm()
                }
                return nil // swallow the event
            }

            // Monitor modifier changes (for modifier-only hotkeys)
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
                guard let self, self.isRecording else { return event }

                let flags = event.modifierFlags
                let modRaw = self.modifierFlagsToRaw(flags)

                let currentBitCount = self.popcount(modRaw)
                let peakBitCount = self.popcount(self.peakModifiers)

                if modRaw != 0 {
                    // Only update if we have MORE modifiers than before (building up the combo)
                    // or if this is a fresh start
                    if currentBitCount >= peakBitCount || self.peakModifiers == 0 {
                        self.peakModifiers = modRaw
                        self.peakKeyCode = -1
                        self.parent.pendingKeyCode = -1
                        self.parent.pendingModifiers = modRaw
                        self.parent.displayText = self.buildDisplayString(modifiers: modRaw, keyCode: -1)
                    }
                    // Reset the confirm timer — user is still pressing keys
                    self.confirmTimer?.invalidate()
                } else {
                    // All modifiers released — confirm the peak combination after a short delay
                    // so the user doesn't have to release all keys at the exact same time
                    if self.peakModifiers != 0 {
                        self.parent.pendingModifiers = self.peakModifiers
                        self.parent.pendingKeyCode = self.peakKeyCode
                        self.scheduleConfirm(delay: 0.3)
                    }
                }
                return event
            }
        }

        func stopMonitoring() {
            if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
            if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
            confirmTimer?.invalidate()
            confirmTimer = nil
            peakModifiers = 0
            peakKeyCode = -1
        }

        private func popcount(_ value: Int) -> Int {
            var n = value
            var count = 0
            while n != 0 { count += n & 1; n >>= 1 }
            return count
        }

        private func scheduleConfirm(delay: TimeInterval = 1.5) {
            confirmTimer?.invalidate()
            confirmTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self, self.isRecording else { return }
                DispatchQueue.main.async {
                    self.parent.onConfirm()
                }
            }
        }

        private func modifierFlagsToRaw(_ flags: NSEvent.ModifierFlags) -> Int {
            var raw: UInt64 = 0
            if flags.contains(.function) { raw |= CGEventFlags.maskSecondaryFn.rawValue }
            if flags.contains(.control) { raw |= CGEventFlags.maskControl.rawValue }
            if flags.contains(.option) { raw |= CGEventFlags.maskAlternate.rawValue }
            if flags.contains(.shift) { raw |= CGEventFlags.maskShift.rawValue }
            if flags.contains(.command) { raw |= CGEventFlags.maskCommand.rawValue }
            return Int(raw)
        }

        private func buildDisplayString(modifiers: Int, keyCode: Int) -> String {
            let flags = CGEventFlags(rawValue: UInt64(modifiers))
            var parts: [String] = []
            if flags.contains(.maskSecondaryFn) { parts.append("Fn") }
            if flags.contains(.maskControl) { parts.append("Control") }
            if flags.contains(.maskAlternate) { parts.append("Option") }
            if flags.contains(.maskShift) { parts.append("Shift") }
            if flags.contains(.maskCommand) { parts.append("Command") }
            if keyCode >= 0 {
                parts.append(AppSettings.keyCodeToString(UInt16(keyCode)))
            }
            return parts.joined(separator: " + ")
        }

        deinit {
            stopMonitoring()
        }
    }

    // Minimal NSView subclass to hook into view lifecycle
    class RecorderView: NSView {
        weak var delegate: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Start/stop monitoring based on recording state — driven by updateNSView
        }

        override func removeFromSuperview() {
            delegate?.stopMonitoring()
            super.removeFromSuperview()
        }
    }
}

// Extension to start/stop monitoring when isRecording changes
extension HotkeyRecorderNSView.Coordinator {
    func update() {
        if isRecording {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }
}
