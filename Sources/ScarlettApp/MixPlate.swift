import SwiftUI

/// Where the open mix's tab sits, in the "mixBlock" coordinate space of the
/// tab row and panel together.
struct OpenTabFrameKey: PreferenceKey {
    static var defaultValue: CGRect?
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

/// The outline of the mix panel with the open tab rising out of its top edge,
/// as one shape: the tab and the panel share one edge, with small rounded
/// inside corners where they meet.
struct OpenTabPlate: Shape {
    var tabX: CGFloat
    var tabWidth: CGFloat
    /// Height of the tab row above the panel.
    let tabHeight: CGFloat
    /// False before the tab has been measured: just the panel.
    let hasTab: Bool
    var radius: CGFloat = 6
    var fillet: CGFloat = 5

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(tabX, tabWidth) }
        set { tabX = newValue.first; tabWidth = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let r = radius, f = fillet
        let left = rect.minX, right = rect.maxX, bottom = rect.maxY
        let top = rect.minY, shelf = rect.minY + tabHeight
        var p = Path()
        p.move(to: CGPoint(x: left, y: bottom - r))

        if hasTab {
            let tabLeft = tabX, tabRight = tabX + tabWidth
            if tabLeft <= left + 0.5 {
                // The tab is flush with the panel's left edge: one straight side.
                p.addLine(to: CGPoint(x: left, y: top + r))
                p.addArc(tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: left + r, y: top), radius: r)
            } else {
                p.addLine(to: CGPoint(x: left, y: shelf))
                p.addLine(to: CGPoint(x: tabLeft - f, y: shelf))
                p.addArc(tangent1End: CGPoint(x: tabLeft, y: shelf), tangent2End: CGPoint(x: tabLeft, y: shelf - f), radius: f)
                p.addLine(to: CGPoint(x: tabLeft, y: top + r))
                p.addArc(tangent1End: CGPoint(x: tabLeft, y: top), tangent2End: CGPoint(x: tabLeft + r, y: top), radius: r)
            }
            p.addLine(to: CGPoint(x: tabRight - r, y: top))
            p.addArc(tangent1End: CGPoint(x: tabRight, y: top), tangent2End: CGPoint(x: tabRight, y: top + r), radius: r)
            p.addLine(to: CGPoint(x: tabRight, y: shelf - f))
            p.addArc(tangent1End: CGPoint(x: tabRight, y: shelf), tangent2End: CGPoint(x: tabRight + f, y: shelf), radius: f)
        } else {
            p.addLine(to: CGPoint(x: left, y: shelf))
        }

        p.addLine(to: CGPoint(x: right - r, y: shelf))
        p.addArc(tangent1End: CGPoint(x: right, y: shelf), tangent2End: CGPoint(x: right, y: shelf + r), radius: r)
        p.addLine(to: CGPoint(x: right, y: bottom - r))
        p.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: right - r, y: bottom), radius: r)
        p.addLine(to: CGPoint(x: left + r, y: bottom))
        p.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: left, y: bottom - r), radius: r)
        p.closeSubpath()
        return p
    }
}

extension MixPlate {
    /// The plate's grey at each height as (position 0…1, white), the junction
    /// being where the tab ends and the panel starts.
    static func faceStops(junction: Double) -> [(location: Double, white: Double)] {
        [(0, 0.262), (junction, 0.215), (junction + (1 - junction) * 0.33, 0.158), (1, 0.105)]
    }

    /// The plate's grey at `fraction` of the way down the block.
    static func face(at fraction: Double, junction: Double) -> Color {
        let stops = faceStops(junction: junction)
        let t = min(max(fraction, 0), 1)
        for (lower, upper) in zip(stops, stops.dropFirst()) where t <= upper.location {
            let span = upper.location - lower.location
            let u = span > 0 ? (t - lower.location) / span : 0
            return Color(white: lower.white + (upper.white - lower.white) * u)
        }
        return Color(white: stops.last?.white ?? 0.1)
    }
}

/// The raised plate behind the open tab and the mix panel, drawn once so they
/// read as a single piece: one lit gradient from the top of the tab to the
/// bottom of the panel, one bevel around the whole outline, one shadow.  The
/// mix's colour is a faint wash falling from the tab's line through into the
/// panel.
struct MixPlate: View {
    let tab: CGRect?
    let tabHeight: CGFloat
    let glow: Color

    var body: some View {
        GeometryReader { geo in
            let height = max(geo.size.height, 1)
            let junction = Double(min(tabHeight / height, 0.5))
            let strength = mixGlowStrength(glow)
            let plate = OpenTabPlate(tabX: tab?.minX ?? 0, tabWidth: tab?.width ?? 0,
                                     tabHeight: tabHeight, hasTab: tab != nil)
            plate
                .fill(LinearGradient(
                    stops: Self.faceStops(junction: junction).map {
                        .init(color: Color(white: $0.white), location: $0.location)
                    },
                    startPoint: .top, endPoint: .bottom))
                .overlay {
                    plate.fill(LinearGradient(
                        stops: [.init(color: glow.opacity(0.10 * strength), location: 0),
                                .init(color: glow.opacity(0.05 * strength), location: junction),
                                .init(color: glow.opacity(0), location: junction + (1 - junction) * 0.25)],
                        startPoint: .top, endPoint: .bottom))
                }
                .overlay {
                    plate.stroke(LinearGradient(
                        stops: [.init(color: Color.white.opacity(0.34), location: 0),
                                .init(color: Color.white.opacity(0.12), location: junction + 0.04),
                                .init(color: Color.black.opacity(0.75), location: 1)],
                        startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.65), radius: 8, y: 5)
                .animation(.easeInOut(duration: 0.18), value: tab)
        }
        .allowsHitTesting(false)
    }
}

/// The analog look's tab: the open one is cut from the same plate as the panel
/// (it is drawn by `MixPlate`, so only the others use this), and the others sit
/// lower and darker.
struct AnalogTabFace: View {
    let selected: Bool

    var body: some View {
        FolderTabShape()
            .fill(LinearGradient(
                colors: selected ? [Color(white: 0.255), Theme.faceTop] : [Color(white: 0.20), Color(white: 0.165)],
                startPoint: .top, endPoint: .bottom))
            .overlay {
                FolderTabShape(inset: 0.5)
                    .stroke(LinearGradient(
                        colors: [Color.white.opacity(selected ? 0.32 : 0.20), Color.white.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(selected ? 0.35 : 0.5), radius: 3, y: -1)
    }
}

/// A tab's colour as a lit line along its top: bright and glowing on the open
/// tab, dimmer on the others.
struct TabGlowLine: View {
    let color: Color
    let selected: Bool

    var body: some View {
        Capsule()
            .fill(color)
            .frame(height: 3)
            .padding(.horizontal, 6)
            .shadow(color: color.opacity(selected ? 0.75 : 0.4), radius: selected ? 4 : 3)
            .shadow(color: color.opacity(selected ? 0.3 : 0), radius: selected ? 9 : 0)
            .opacity(selected ? 1 : 0.7)
    }
}
