import AppKit
import SwiftUI

final class OverlayWindowController {
    private var window: NSWindow?
    private var hostingView: NSHostingView<OverlayContentView>?

    @MainActor
    func show(status: AppStatus) {
        if window == nil {
            let contentView = OverlayContentView(status: status)
            let hosting = NSHostingView(rootView: contentView)
            hosting.frame = NSRect(x: 0, y: 0, width: 220, height: 44)

            let w = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .floating
            w.collectionBehavior = [.canJoinAllSpaces, .stationary]
            w.isReleasedWhenClosed = false
            w.ignoresMouseEvents = true
            w.contentView = hosting

            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.midX - 110
                let y = screenFrame.maxY - 60
                w.setFrameOrigin(NSPoint(x: x, y: y))
            }

            self.window = w
            self.hostingView = hosting
        }

        hostingView?.rootView = OverlayContentView(status: status)
        window?.orderFront(nil)
    }

    @MainActor
    func hide() {
        window?.orderOut(nil)
    }
}

struct OverlayContentView: View {
    let status: AppStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .font(.system(size: 14, weight: .semibold))
            Text(statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    private var iconName: String {
        switch status {
        case .recording: return "mic.fill"
        case .transcribing: return "brain"
        case .injecting: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        default: return "mic"
        }
    }

    private var iconColor: Color {
        switch status {
        case .recording: return .red
        case .transcribing: return .orange
        case .injecting: return .green
        case .error: return .red
        default: return .primary
        }
    }

    private var statusText: String {
        switch status {
        case .recording: return "Aufnahme..."
        case .transcribing: return "Transkribiere..."
        case .injecting: return "Fertig"
        case .error(let msg): return String(msg.prefix(30))
        default: return ""
        }
    }
}
