import SwiftUI
import AppKit

/// Shows `cursor` while the pointer is over the view.  Macs keep the arrow over
/// ordinary buttons; this is for custom controls that nothing else marks as
/// clickable or draggable.
private struct CursorModifier: ViewModifier {
    let cursor: NSCursor
    let enabled: Bool
    @State private var active = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside, !active, enabled {
                    cursor.push()
                    active = true
                } else if !inside, active {
                    NSCursor.pop()
                    active = false
                }
            }
            // A control turned off while the pointer is on it drops the cursor too.
            .onChange(of: enabled) {
                if !enabled, active {
                    NSCursor.pop()
                    active = false
                }
            }
            // A view removed while the pointer is on it never gets a hover end.
            .onDisappear {
                if active {
                    NSCursor.pop()
                    active = false
                }
            }
    }
}

extension View {
    func cursor(_ cursor: NSCursor, when enabled: Bool = true) -> some View {
        modifier(CursorModifier(cursor: cursor, enabled: enabled))
    }
}
