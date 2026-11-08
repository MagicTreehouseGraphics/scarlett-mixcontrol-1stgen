import SwiftUI
import AppKit

/// Placed in the background of a horizontal `ScrollView`'s content, it makes a
/// plain vertical scroll (mouse wheel or trackpad swipe) over that scroll view
/// scroll it sideways, so Shift isn't needed.  Horizontal gestures still work
/// as usual, and when the view can't scroll any further the event passes on,
/// so an outer vertical scroll view still gets it.
struct SidewaysScrollWheel: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Redirector() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Redirector: NSView {
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.redirected(event) ?? event
            }
        }

        deinit { removeMonitor() }

        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private var scrollView: NSScrollView? {
            if let enclosing = enclosingScrollView { return enclosing }
            var view: NSView? = superview
            while let current = view {
                if let scroll = current as? NSScrollView { return scroll }
                view = current.superview
            }
            return nil
        }

        /// The event to carry on with, or nil when it has been used up.
        private func redirected(_ event: NSEvent) -> NSEvent? {
            guard event.window === window,
                  let scrollView, let document = scrollView.documentView else { return event }
            let point = scrollView.convert(event.locationInWindow, from: nil)
            guard scrollView.bounds.contains(point) else { return event }

            let dy = event.scrollingDeltaY
            guard abs(dy) > abs(event.scrollingDeltaX) else { return event }

            let clip = scrollView.contentView
            let maxX = document.frame.width - clip.bounds.width
            guard maxX > 0 else { return event }

            // A notched mouse wheel reports lines, a trackpad reports points.
            let delta = event.hasPreciseScrollingDeltas ? dy : dy * 12
            let current = clip.bounds.origin.x
            let target = min(max(current - delta, 0), maxX)
            guard target != current else { return event }

            clip.scroll(to: NSPoint(x: target, y: clip.bounds.origin.y))
            scrollView.reflectScrolledClipView(clip)
            return nil
        }
    }
}
