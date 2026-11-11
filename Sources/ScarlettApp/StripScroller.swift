import SwiftUI

/// A row of strips scrolling sideways, shared by the mixer and the routing
/// page.  Where strips are out of view, that edge fades and a key set into the
/// panel's wall pushes out of it; it scrolls to them, and slides back in once
/// the end is reached.  A plain scroll wheel scrolls the row, without Shift.
struct StripScroller<Content: View>: View {
    /// Identity of each unit (a strip, or a pair of them), in order.
    let ids: [Int]
    /// How many things a unit holds, for the key's tooltip.
    let size: (Int) -> Int
    /// What the units hold ("channel", "output"), for the key's tooltip.
    let noun: String
    /// The named coordinate space of the plate behind the page, its height, and
    /// the height of the tab row above the panel: the keys take the plate's grey
    /// at their height from these.
    let blockSpace: String
    let blockHeight: CGFloat
    let tabRowHeight: CGFloat
    @ViewBuilder let content: (Int) -> Content

    @State private var overflow = StripOverflow()
    @State private var tracker = StripTracker()
    /// The counts the keys last showed, kept while a key slides away so its
    /// tooltip doesn't flash "0" on the way out.
    @State private var shownLeft = 0
    @State private var shownRight = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ids, id: \.self) { id in
                        content(id)
                            .background {
                                GeometryReader { geo in
                                    Color.clear.preference(key: StripFramesKey.self,
                                                           value: [id: geo.frame(in: .named("strips"))])
                                }
                            }
                    }
                }
                .padding(.vertical, StripLayout.pinnedOutset)
                // Room for the cards' shadows, which the scroll view would clip.
                .padding(.horizontal, 6)
                .background(SidewaysScrollWheel())
            }
            .coordinateSpace(name: "strips")
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                tracker.viewport = width
                update()
            }
            .onPreferenceChange(StripFramesKey.self) { frames in
                tracker.frames = frames
                update()
            }
            .overlay {
                // Both keys are always there; the one with nothing to reveal
                // is slid into the edge, where this clips it.
                ZStack {
                    edge(leading: true, active: overflow.leftTarget != nil,
                         count: shownLeft, target: overflow.leftTarget, proxy: proxy)
                    edge(leading: false, active: overflow.rightTarget != nil,
                         count: shownRight, target: overflow.rightTarget, proxy: proxy)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, -4)
                .clipped()
            }
        }
    }

    private func update() {
        let new = tracker.overflow(sizeOf: size)
        if new.leftCount > 0, shownLeft != new.leftCount { shownLeft = new.leftCount }
        if new.rightCount > 0, shownRight != new.rightCount { shownRight = new.rightCount }
        if new != overflow { overflow = new }
    }

    /// The edge cue: the strips fade toward the edge, and a key set into the
    /// panel's side wall, an arrow on a piece of the panel, scrolls to what is
    /// out of view.
    private func edge(leading: Bool, active: Bool, count: Int, target: Int?,
                      proxy: ScrollViewProxy) -> some View {
        let width: CGFloat = 28
        // The key slides with a spring; the fade and the key's body come and go
        // more slowly than the slide, so they never pop.
        let slide: Animation = active
            ? .spring(response: 0.5, dampingFraction: 0.7)
            : .easeIn(duration: 0.3)
        let soften: Animation = .easeInOut(duration: active ? 0.8 : 0.6)
        return ZStack(alignment: leading ? .leading : .trailing) {
            LinearGradient(colors: [Color.black.opacity(0.8), Color.black.opacity(0.35), Color.black.opacity(0)],
                           startPoint: leading ? .leading : .trailing,
                           endPoint: leading ? .trailing : .leading)
                .frame(width: 88)
                .opacity(active ? 1 : 0)
                .animation(soften, value: active)
                .allowsHitTesting(false)
            Button {
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.32)) {
                    proxy.scrollTo(target, anchor: leading ? .trailing : .leading)
                }
            } label: {
                Image(systemName: leading ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.muteActive)
                    .shadow(color: Theme.muteActive.opacity(0.8), radius: 4)
                    // The arrow comes in after the key has formed, and goes before
                    // it, so it is never on its own.
                    .opacity(active ? 1 : 0)
                    .animation(soften.delay(active ? 0.3 : 0), value: active)
                    .frame(width: width, height: 64)
                    .background(alignment: leading ? .leading : .trailing) {
                        // The key is a piece of the panel: it runs back to the
                        // panel's wall and curves into the margin beside the strips.
                        EdgeKeyPocket(leading: leading, blockSpace: blockSpace,
                                      blockHeight: blockHeight, tabRowHeight: tabRowHeight)
                            .frame(width: width + 4, height: 64 + 10)
                            .offset(x: leading ? -4 : 4)
                            .opacity(active ? 1 : 0)
                            .animation(soften, value: active)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(EdgeKeyPressStyle(leading: leading))
            .cursor(.pointingHand)
            .offset(x: active ? 0 : (leading ? -width - 6 : width + 6))
            .animation(slide, value: active)
            .allowsHitTesting(active)
            .help("\(count) more \(noun)\(count == 1 ? "" : "s") \(leading ? "to the left" : "to the right")")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: leading ? .leading : .trailing)
    }
}
