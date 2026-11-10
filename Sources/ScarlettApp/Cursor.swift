import SwiftUI
import AppKit

/// Decides when a control's cursor is pushed on and popped off AppKit's cursor
/// stack, kept free of AppKit so the sequences can be tested.  Every push has
/// exactly one pop, whatever order hovering, dragging, disabling and removal
/// happen in; an unbalanced stack leaves the cursor stuck as a hand.
struct CursorTracker {
    enum Action: Equatable { case push, pop, swap }

    private(set) var active = false
    private var leftWhileHolding = false

    /// The pointer entered or left the control.
    mutating func hover(inside: Bool, enabled: Bool, holding: Bool) -> Action? {
        if inside {
            leftWhileHolding = false
            guard !active, enabled else { return nil }
            active = true
            return .push
        }
        guard active else { return nil }
        if holding {
            leftWhileHolding = true
            return nil
        }
        return release()
    }

    /// The cursor to show changed (the hand closing or opening).
    mutating func cursorChanged() -> Action? { active ? .swap : nil }

    /// A drag began or ended.  If the pointer left during it, the cursor goes now.
    mutating func holdingChanged(holding: Bool) -> Action? {
        !holding && leftWhileHolding ? release() : nil
    }

    mutating func enabledChanged(enabled: Bool) -> Action? {
        !enabled && active ? release() : nil
    }

    /// The control was removed while the pointer may have been on it.
    mutating func disappeared() -> Action? { active ? release() : nil }

    private mutating func release() -> Action {
        active = false
        leftWhileHolding = false
        return .pop
    }
}

/// Shows `cursor` while the pointer is over the view.  Macs keep the arrow over
/// ordinary buttons; this is for custom controls that nothing else marks as
/// clickable or draggable.
private struct CursorModifier: ViewModifier {
    let cursor: NSCursor
    let enabled: Bool
    /// True while the control is being dragged: the cursor then stays even if
    /// the pointer leaves the view, and goes when the drag ends.
    let holding: Bool

    @State private var tracker = CursorTracker()

    func body(content: Content) -> some View {
        content
            .onHover { apply(tracker.hover(inside: $0, enabled: enabled, holding: holding)) }
            .onChange(of: cursor) { apply(tracker.cursorChanged()) }
            .onChange(of: holding) { apply(tracker.holdingChanged(holding: holding)) }
            .onChange(of: enabled) { apply(tracker.enabledChanged(enabled: enabled)) }
            .onDisappear { apply(tracker.disappeared()) }
    }

    private func apply(_ action: CursorTracker.Action?) {
        switch action {
        case .push: cursor.push()
        case .pop: NSCursor.pop()
        case .swap:
            NSCursor.pop()
            cursor.push()
        case nil: break
        }
    }
}

extension View {
    func cursor(_ cursor: NSCursor, when enabled: Bool = true, holding: Bool = false) -> some View {
        modifier(CursorModifier(cursor: cursor, enabled: enabled, holding: holding))
    }

    /// The open hand over something that can be dragged, closing while it is.
    func grabCursor(dragging: Bool, when enabled: Bool = true) -> some View {
        cursor(dragging ? .closedHand : .openHand, when: enabled, holding: dragging)
    }
}
