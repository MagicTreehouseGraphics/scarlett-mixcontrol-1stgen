import SwiftUI

/// A compact horizontal slider.  Drag anywhere to set the value, or grab the
/// thumb to move it from where it is; double-click calls `onReset`.  Built
/// from gestures rather than `Slider`, whose AppKit control swallows the
/// double-click.
struct HorizontalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Where the filled part of the track starts.  Defaults to the left end;
    /// a pan slider starts it at its center.
    var origin: Double?
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onReset: (() -> Void)?

    @Environment(\.isEnabled) private var isEnabled
    @State private var grabOffset: CGFloat?

    private let thumbSize: CGFloat = 11
    private let trackHeight: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.width - thumbSize)
            let thumbX = x(for: value, usable: usable)
            let originX = x(for: origin ?? range.lowerBound, usable: usable)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.faderTrack)
                    .frame(height: trackHeight)
                Capsule()
                    .fill(Theme.muteActive)
                    .frame(width: abs(thumbX - originX), height: trackHeight)
                    .offset(x: min(thumbX, originX))
                Circle()
                    .fill(Theme.faderKnob)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: Theme.faderKnobShadow, radius: 1, y: 0.5)
                    .offset(x: thumbX - thumbSize / 2)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if grabOffset == nil {
                            // Grabbing the thumb keeps it under the pointer;
                            // anywhere else jumps it there.
                            let offset = drag.startLocation.x - thumbX
                            grabOffset = abs(offset) <= thumbSize ? offset : 0
                            onEditingChanged(true)
                        }
                        value = self.value(atX: drag.location.x - (grabOffset ?? 0), usable: usable)
                    }
                    .onEnded { _ in
                        grabOffset = nil
                        onEditingChanged(false)
                    }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { onReset?() })
        }
        .frame(height: 14)
        .opacity(isEnabled ? 1 : 0.4)
        .cursor(.resizeLeftRight, when: isEnabled)
    }

    private func x(for value: Double, usable: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        let fraction = span > 0 ? (value - range.lowerBound) / span : 0
        return thumbSize / 2 + CGFloat(max(0, min(1, fraction))) * usable
    }

    private func value(atX x: CGFloat, usable: CGFloat) -> Double {
        let fraction = max(0, min(1, Double((x - thumbSize / 2) / usable)))
        return range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }
}
