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

    /// A strip pair counts as out of view as soon as any of it is cut off.
    func overflow(channelBound: Int) -> StripOverflow {
        guard viewport > 0, !frames.isEmpty else { return StripOverflow() }
        let channels = { (left: Int) in min(2, channelBound - left) }
        let hiddenLeft = frames.filter { $0.value.minX < -1 }.keys.sorted()
        let hiddenRight = frames.filter { $0.value.maxX > viewport + 1 }.keys.sorted()
        return StripOverflow(
            leftTarget: hiddenLeft.last,
            rightTarget: hiddenRight.first,
            leftCount: hiddenLeft.reduce(0) { $0 + channels($1) },
            rightCount: hiddenRight.reduce(0) { $0 + channels($1) })
    }
}

/// A tab set against one side of a panel, flat where it meets the side and
/// rounded on its free edge.
struct EdgeTabShape: Shape {
    /// True when it is attached to the left side.
    let leading: Bool
    var radius: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width, rect.height / 2)
        var p = Path()
        if leading {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
            p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX, y: rect.minY + r), radius: r)
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX + r, y: rect.maxY), radius: r)
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}

/// The pocket the edge key sits in: darker than the panel, shaded along its
/// top and inner edge and lit along its lower lip, so it reads as cut into
/// the side wall rather than stuck on top of it.
struct EdgeKeyPocket: View {
    let leading: Bool

    var body: some View {
        let shape = EdgeTabShape(leading: leading)
        shape
            .fill(LinearGradient(
                colors: [Color.black.opacity(0.78), Color.black.opacity(0.52)],
                startPoint: .top, endPoint: .bottom))
            .overlay {
                // Shadow cast into the pocket from its wall.
                shape.fill(LinearGradient(
                    colors: [Color.black.opacity(0.55), Color.clear],
                    startPoint: leading ? .leading : .trailing,
                    endPoint: leading ? .trailing : .leading))
            }
            .overlay {
                shape.stroke(LinearGradient(
                    stops: [.init(color: Color.black.opacity(0.9), location: 0),
                            .init(color: Color.white.opacity(0.04), location: 0.55),
                            .init(color: Color.white.opacity(0.16), location: 1)],
                    startPoint: .top, endPoint: .bottom), lineWidth: 1)
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
    }
}
