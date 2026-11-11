import SwiftUI

/// Where each strip pair sits in the scrolling strips' own coordinate space,
/// keyed by its left channel.
struct StripFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// How many channels are scrolled out of view at each end, and the strip pair
/// to scroll to to reveal them.
struct StripOverflow: Equatable {
    var leftTarget: Int?
    var rightTarget: Int?
    var leftCount = 0
    var rightCount = 0
}

/// The latest strip positions and viewport width, kept out of `@State` so that
/// scrolling, which changes them on every frame, doesn't re-render the mixer.
final class StripTracker {
    var frames: [Int: CGRect] = [:]
    var viewport: CGFloat = 0

    /// A unit counts as out of view as soon as any of it is cut off.  `sizeOf`
    /// says how many things a unit holds.
    func overflow(sizeOf: (Int) -> Int) -> StripOverflow {
        guard viewport > 0, !frames.isEmpty else { return StripOverflow() }
        let hiddenLeft = frames.filter { $0.value.minX < -1 }.keys.sorted()
        let hiddenRight = frames.filter { $0.value.maxX > viewport + 1 }.keys.sorted()
        return StripOverflow(
            leftTarget: hiddenLeft.last,
            rightTarget: hiddenRight.first,
            leftCount: hiddenLeft.reduce(0) { $0 + sizeOf($1) },
            rightCount: hiddenRight.reduce(0) { $0 + sizeOf($1) })
    }
}

/// The key's outline: a tab of the panel's own material reaching in from the
/// side over the strips.  Its free end has rounded corners, and where it meets
/// the margin around the strips it curves smoothly into it, as the mix tabs do
/// where they meet the panel.  `rect` runs from the panel's outer wall (a
/// margin's width beyond where the strips start) to the key's free end, and is
/// the key's height plus a fillet above and below.
struct EdgeKeyShape {
    /// True when attached to the left side.
    let leading: Bool
    /// Width of the margin between the panel's wall and the strips.
    var margin: CGFloat = 4
    var fillet: CGFloat = 5
    var radius: CGFloat = 9

    private func points(in rect: CGRect) -> (x: (CGFloat) -> CGFloat, wall: CGFloat, join: CGFloat, free: CGFloat) {
        // Written for the right side, then mirrored for the left.
        let mirror = { (x: CGFloat) in leading ? rect.minX + rect.maxX - x : x }
        return (mirror, mirror(rect.maxX), mirror(rect.maxX - margin), mirror(rect.minX))
    }

    /// The outline from the top join to the bottom join, along the free end only.
    func outline(in rect: CGRect) -> Path {
        let (x, _, join, free) = points(in: rect)
        let f = fillet, r = radius
        let top = rect.minY, bottom = rect.maxY
        let dir: CGFloat = leading ? 1 : -1        // from the wall toward the free end
        var p = Path()
        p.move(to: CGPoint(x: join, y: top))
        p.addArc(tangent1End: CGPoint(x: join, y: top + f), tangent2End: CGPoint(x: join + dir * f, y: top + f), radius: f)
        p.addLine(to: CGPoint(x: free - dir * r, y: top + f))
        p.addArc(tangent1End: CGPoint(x: free, y: top + f), tangent2End: CGPoint(x: free, y: top + f + r), radius: r)
        p.addLine(to: CGPoint(x: free, y: bottom - f - r))
        p.addArc(tangent1End: CGPoint(x: free, y: bottom - f), tangent2End: CGPoint(x: free - dir * r, y: bottom - f), radius: r)
        p.addLine(to: CGPoint(x: join + dir * f, y: bottom - f))
        p.addArc(tangent1End: CGPoint(x: join, y: bottom - f), tangent2End: CGPoint(x: join, y: bottom), radius: f)
        _ = x
        return p
    }

    /// The filled shape: the outline closed back along the wall.
    func fill(in rect: CGRect) -> Path {
        let (_, wall, join, _) = points(in: rect)
        var p = outline(in: rect)
        p.addLine(to: CGPoint(x: wall, y: rect.maxY))
        p.addLine(to: CGPoint(x: wall, y: rect.minY))
        p.addLine(to: CGPoint(x: join, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// The key's body, drawn in the panel's own grey: the plate's gradient taken at
/// the height the key sits, so it flows on from the margin around the strips
/// instead of reading as a separate box, with the plate's bevel round its free
/// edge and a soft shadow onto the strips it covers.
struct EdgeKeyPocket: View {
    let leading: Bool
    /// The named coordinate space of the plate the key's grey is taken from.
    let blockSpace: String
    /// Height of the tab row + panel block, and of its tab row, to find the
    /// plate's grey at this height.
    let blockHeight: CGFloat
    let tabRowHeight: CGFloat

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let frame = geo.frame(in: .named(blockSpace))
            let height = max(blockHeight, 1)
            let junction = Double(min(tabRowHeight / height, 0.5))
            let top = MixPlate.face(at: Double(frame.minY / height), junction: junction)
            let bottom = MixPlate.face(at: Double(frame.maxY / height), junction: junction)
            let shape = EdgeKeyShape(leading: leading)
            ZStack {
                shape.fill(in: rect)
                    .fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color.black.opacity(0.5), radius: 4, x: leading ? 2 : -2)
                shape.outline(in: rect)
                    .stroke(LinearGradient(
                        stops: [.init(color: Color.white.opacity(0.26), location: 0),
                                .init(color: Color.white.opacity(0.08), location: 0.5),
                                .init(color: Color.black.opacity(0.55), location: 1)],
                        startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
        }
    }
}

/// Presses the key a little further into its pocket.
struct EdgeKeyPressStyle: ButtonStyle {
    let leading: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(x: configuration.isPressed ? (leading ? -2 : 2) : 0)
            .brightness(configuration.isPressed ? -0.18 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .cursor(.pointingHand)
    }
}
