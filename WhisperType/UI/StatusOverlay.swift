import AppKit
import SwiftUI

final class OverlayWindowController {
    private var window: NSWindow?
    private var hostingView: NSHostingView<OverlayContentView>?

    @MainActor
    func show(status: AppStatus) {
        if window == nil {
            let hosting = NSHostingView(rootView: OverlayContentView(status: status))

            let w = NSWindow(
                contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
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

            self.window = w
            self.hostingView = hosting
        }

        hostingView?.rootView = OverlayContentView(status: status)
        hostingView?.layoutSubtreeIfNeeded()
        let fitting = hostingView?.fittingSize ?? NSSize(width: 220, height: 44)
        window?.setContentSize(fitting)
        repositionWindow(size: fitting)
        window?.orderFront(nil)
    }

    @MainActor
    private func repositionWindow(size: NSSize) {
        guard let window, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let bottomInset: CGFloat = 80
        let y = visible.minY + bottomInset
        window.setFrameOrigin(NSPoint(x: x, y: y))
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
        case .preparingModel: return "arrow.down.doc"
        case .postProcessing: return "sparkles"
        case .injecting: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        default: return "mic"
        }
    }

    private var iconColor: Color {
        switch status {
        case .recording: return .red
        case .transcribing: return .orange
        case .preparingModel: return .orange
        case .postProcessing: return .purple
        case .injecting: return .green
        case .error: return .red
        default: return .primary
        }
    }

    private var statusText: String {
        switch status {
        case .recording: return NSLocalizedString("status.recording", comment: "")
        case .transcribing: return NSLocalizedString("status.transcribing", comment: "")
        case .preparingModel: return NSLocalizedString("status.preparing_model", comment: "")
        case .postProcessing: return NSLocalizedString("status.enhancing", comment: "")
        case .injecting: return NSLocalizedString("status.done", comment: "")
        case .error(let msg): return String(msg.prefix(30))
        default: return ""
        }
    }
}
