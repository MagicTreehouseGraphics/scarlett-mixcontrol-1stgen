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
