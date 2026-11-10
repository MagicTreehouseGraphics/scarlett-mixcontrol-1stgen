import SwiftUI

/// A vertical dB axis shared by a strip's fader, meter and scale, so all
/// three agree on where every level sits.
///
/// The spacing follows the usual console / Focusrite Control meter law:
/// even 6 dB steps from the top down to -30 dB, where the detail matters,
/// then a compressed -30 / -36 / -48 / -60 tail and one last step down to
/// `off` (-∞), so a fader pulled all the way down mutes.  Every axis has
/// the same physical extent (from `inset` to `height - inset`, the knob's
/// centre line at either end of its travel), so tracks and meters line up
/// from strip to strip; only the top value differs.
struct DbAxis {
    /// Scale breakpoints, top to bottom.  The first is the axis' top value.
    let breakpoints: [Double]

    /// Matrix channel gain (input and DAW strips): up to +6 dB.
    static let gain = DbAxis(breakpoints: [6] + Self.levels)
    /// Output attenuation (Monitor, Phones, line outs): 0 dB at the top.
    static let attenuation = DbAxis(breakpoints: Self.levels)

    /// The bottom of every axis: the device treats -128 dB as off.
    static let off: Double = -128
    /// Quietest level meters and peak readouts show; below it is the
    /// device's noise floor (shown as -∞).
    static let meterFloor: Double = -60
    /// Peaks at or above this count as a clip: 0.999 of full scale, the
    /// threshold Focusrite's MixControl uses.  The device's meters top out
    /// at full scale, so a level can reach 0 dBFS but never read above it.
    static let clip: Double = 20 * log10(0.999)

    private static let levels: [Double] = [0, -6, -12, -18, -24, -30, -36, -48, -60, off]
    /// Relative height of the segment below breakpoint `db`: full steps
    /// down to -30 dB, a little over half a step for each in the tail, and
    /// a short last step from -60 dB to off.
    private static func weight(below db: Double) -> Double {
        if db > -30 { return 1 }
        if db > -60 { return 0.55 }
        return 0.28
    }

    /// Half the analog cap, the taller one, so either look's cap fits at the ends.
    static let inset: CGFloat = VerticalFader.knobHeight / 2

    var top: Double { breakpoints.first ?? 0 }
    var bottom: Double { breakpoints.last ?? Self.off }

    /// Marks at the breakpoints (all but `off`), and minor ticks halfway
    /// between them.
    var majorTicks: [Double] { breakpoints.filter { $0 > Self.off } }
    var minorTicks: [Double] {
        zip(majorTicks, majorTicks.dropFirst()).map { ($0 + $1) / 2 }
    }

    /// Readout for a fader level: "-7.0", "+3.0", or "-∞" at the bottom.
    static func format(_ db: Double) -> String {
        if db <= off { return "−∞" }
        let tenths = (db * 10).rounded() / 10
        if tenths == 0 { return "0.0" }   // not "-0.0"
        return String(format: tenths > 0 ? "+%.1f" : "%.1f", tenths)
    }

    /// Readout for a max peak: "-12.3", "CLIP" at full scale, or "-∞"
    /// below the meter floor.
    static func formatPeak(_ db: Double) -> String {
        if db >= clip { return "CLIP" }
        return db.isFinite && db > meterFloor ? String(format: "%.1f", db) : "−∞"
    }

    /// Position of `db` from the bottom of the axis, 0...1.
    private func fraction(_ db: Double) -> Double {
        let value = db.isFinite ? min(max(db, bottom), top) : bottom
        var below = 0.0, total = 0.0
        for (upper, lower) in zip(breakpoints, breakpoints.dropFirst()) {
            let w = Self.weight(below: upper)
            total += w
            if value >= upper { below += w }
            else if value > lower { below += w * (value - lower) / (upper - lower) }
        }
        return total > 0 ? below / total : 0
    }

    /// Vertical position of `db` in a column of `height`, from the top.
    func y(_ db: Double, height: CGFloat) -> CGFloat {
        Self.inset + (height - 2 * Self.inset) * CGFloat(1 - fraction(db))
    }

    /// Inverse of `y(_:height:)`, clamped to the axis.
    func db(atY y: CGFloat, height: CGFloat) -> Double {
        let target = 1 - Double((y - Self.inset) / (height - 2 * Self.inset))
        // Snap the ends, so the bottom is exactly `off` (mute) and the top
        // exactly the axis' maximum.
        if target <= 0 { return bottom }
        if target >= 1 { return top }
        // `fraction` is monotonic, so bisect rather than invert by hand.
        var lo = bottom, hi = top
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if fraction(mid) < target { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }
}

/// Vertical fader inspired by Focusrite Control 2's mixer strips, covering
/// its `axis`.  Drag anywhere along the column (or on the knob) to set the
/// value; double-click to return to 0 dB.  SwiftUI throttles drag events, so
/// the gesture path doesn't flood the USB queue.
struct VerticalFader: View {
    @Binding var db: Double
    var axis: DbAxis = .gain
    /// Anodised colour for the cap, and the lit line in the slot below it (the
    /// output faders); nil is the matte silver cap of the channel faders.
    var tint: Color?
    @Environment(\.faderHeight) private var height

    static let knobHeight: CGFloat = 32
    private let trackWidth: CGFloat = 11
    private let slotWidth: CGFloat = 1.5
    /// How far the slot stops short of each end of the housing, clear of its
    /// rounded ends.
    private var slotInset: CGFloat { trackWidth / 2 + 4 }
    private let knobWidth: CGFloat = 20
    private var knobHeight: CGFloat { Self.knobHeight }

    var body: some View {
        Group {
            if AppearanceSettings.shared.look == .classic {
                classicFader
            } else {
                analogFader
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    db = axis.db(atY: drag.location.y, height: height)
                }
        )
        .simultaneousGesture(TapGesture(count: 2).onEnded { db = 0 })
    }

    /// The hardware-style fader: a recessed housing, a slot, and a chunky cap.
    private var analogFader: some View {
        // Height comes from `\.faderHeight`, so no GeometryReader (which
        // would force a layout pass on every frame).  Drag-gesture
        // `.location.y` is already in this view's local coordinate space.
        let topY = axis.y(axis.top, height: height)
        let bottomY = axis.y(axis.bottom, height: height)
        let knobY = axis.y(db, height: height)

        return ZStack(alignment: .top) {
            // Unity (0 dB) mark: a short line either side of the track,
            // leaving a gap so it doesn't cross the track itself.
            HStack(spacing: trackWidth + 6) {
                Rectangle().frame(height: 1)
                Rectangle().frame(height: 1)
            }
            .foregroundStyle(Theme.textSecondary.opacity(0.6))
            .frame(width: knobWidth + 4, height: 1)
            .offset(y: axis.y(0, height: height) - 0.5)

            housing
                .frame(width: trackWidth, height: bottomY - topY)
                .offset(y: topY)

            // The slot the cap's stem runs in: a hairline pitch-black cut down
            // the middle of the housing, with a lit lip on its far side.
            HStack(spacing: 0) {
                Capsule().fill(Color.black).frame(width: slotWidth)
                Capsule().fill(Color.white.opacity(0.04)).frame(width: 0.5)
            }
            .frame(height: max(0, bottomY - topY - 2 * slotInset))
            .offset(x: 0.25, y: topY + slotInset)

            if let tint {
                // A lit line in the slot from the cap down, with a soft halo.
                let lineHeight = max(0, bottomY - slotInset - knobY)
                Capsule()
                    .fill(tint.opacity(0.25))
                    .frame(width: slotWidth + 4, height: lineHeight)
                    .offset(y: knobY)
                Capsule()
                    .fill(tint)
                    .frame(width: slotWidth + 0.5, height: lineHeight)
                    .offset(y: knobY)
            }

            // The shadow is cast by a plain silhouette, not by the cap's many
            // gradient layers, which are costly to blur on every redraw.
            ZStack {
                SoftShadow(shape: RoundedRectangle(cornerRadius: 3.5), radius: 5, y: 3.5, opacity: 0.9, layers: 4)
                cap
            }
            .frame(width: knobWidth, height: knobHeight)
            .offset(y: knobY - knobHeight / 2)
        }
        .frame(width: knobWidth + 6, height: height, alignment: .top)
    }

    /// The original fader: a thin flat track, a fill below the cap, and a
    /// small gradient cap.
    private var classicFader: some View {
        let knobHeight: CGFloat = 14
        let trackWidth: CGFloat = 4
        let knobWidth: CGFloat = 30
        let topY = axis.y(axis.top, height: height)
        let bottomY = axis.y(axis.bottom, height: height)
        let knobY = axis.y(db, height: height)

        return ZStack(alignment: .top) {
            HStack(spacing: trackWidth + 6) {
                Rectangle().frame(height: 1)
                Rectangle().frame(height: 1)
            }
            .foregroundStyle(Theme.textSecondary.opacity(0.6))
            .frame(width: knobWidth, height: 1)
            .offset(y: axis.y(0, height: height) - 0.5)

            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.faderTrack)
                .frame(width: trackWidth, height: bottomY - topY)
                .offset(y: topY)

            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.faderTrackFill)
                .frame(width: trackWidth, height: max(0, bottomY - knobY))
                .offset(y: knobY)

            RoundedRectangle(cornerRadius: 2.5)
                .fill(LinearGradient(
                    colors: [Color(white: 0.85), Theme.faderKnob, Color(white: 0.55)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(Rectangle().fill(Color.black.opacity(0.35)).frame(height: 1))
                .frame(width: knobWidth, height: knobHeight)
                .shadow(color: Theme.faderKnobShadow, radius: 1.5, y: 1)
                .offset(y: knobY - knobHeight / 2)
        }
        .frame(width: knobWidth + 6, height: height, alignment: .top)
    }
}

extension VerticalFader {
    /// The track housing: a rounded channel cut into the panel.  Inside it is
    /// darker than the panel, its upper edge throws a shadow down into it, and
    /// light catches the lip at the bottom, so it reads as set in rather than
    /// standing up.  The walls fall away toward the slit in the middle.
    fileprivate var housing: some View {
        let shape = RoundedRectangle(cornerRadius: trackWidth / 2)
        return shape
            .fill(LinearGradient(
                stops: [.init(color: Color(white: 0.135), location: 0),
                        .init(color: Color(white: 0.11), location: 0.32),
                        .init(color: Color(white: 0.085), location: 0.5),
                        .init(color: Color(white: 0.11), location: 0.68),
                        .init(color: Color(white: 0.13), location: 1)],
                startPoint: .leading, endPoint: .trailing))
            .overlay(alignment: .top) {
                // Shadow cast down into the channel by its upper edge.
                LinearGradient(colors: [Color.black.opacity(0.75), Color.black.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 16)
                    .clipShape(shape)
            }
            .overlay {
                // Shadow along the left wall, light from above-left.
                shape.fill(LinearGradient(
                    stops: [.init(color: Color.black.opacity(0.45), location: 0),
                            .init(color: Color.clear, location: 0.35)],
                    startPoint: .leading, endPoint: .trailing))
            }
            .overlay {
                // The panel's cut edge: darkest along the top, fading out
                // toward the bottom rather than turning into a lit ring.
                shape.strokeBorder(LinearGradient(
                    stops: [.init(color: Color.black.opacity(0.95), location: 0),
                            .init(color: Color.black.opacity(0.75), location: 0.6),
                            .init(color: Color.black.opacity(0.45), location: 1)],
                    startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .background(alignment: .bottom) {
                // A hint of light where the panel's surface meets the cut below it.
                Capsule()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: trackWidth - 2, height: 2)
                    .blur(radius: 0.5)
                    .offset(y: 1.5)
            }
    }

    /// The fader cap, shaped like a classic hourglass cap and lit from above:
    /// a bright top lip, two concave scoops with grip ridges meeting at an
    /// inset position line, and a base in shadow.  Matte silver with a dark
    /// line, or anodised `tint` with a bright one.
    fileprivate var cap: some View {
        let shape = RoundedRectangle(cornerRadius: 3.5)
        let base = tint ?? Color(white: 0.80)
        let gloss = tint == nil ? 1.0 : 0.6
        return shape
            .fill(base)
            .overlay {
                VStack(spacing: 0) {
                    // Top lip, facing the light: a hard bright edge.
                    LinearGradient(colors: [Color.white.opacity(0.95 * gloss + 0.05), Color.white.opacity(0.40)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 3)
                    // Upper scoop: turns away from the light toward the line.
                    LinearGradient(colors: [Color.white.opacity(0.22 * gloss), Color.black.opacity(0.34)],
                                   startPoint: .top, endPoint: .bottom)
                        .overlay { ridges }
                    positionLine
                    // Lower scoop: faces up just under the line, so it's brightest there.
                    LinearGradient(colors: [Color.white.opacity(0.62 * gloss), Color.black.opacity(0.12)],
                                   startPoint: .top, endPoint: .bottom)
                        .overlay { ridges }
                    // Base: the cap's lower side, in its own shadow.
                    LinearGradient(colors: [Color.black.opacity(0.46), Color.black.opacity(0.68)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 5)
                }
                .clipShape(shape)
            }
            .overlay {
                // A bright streak down the face, as light catches polished metal.
                shape.fill(LinearGradient(
                    stops: [.init(color: .clear, location: 0),
                            .init(color: Color.white.opacity(0.30 * gloss), location: 0.18),
                            .init(color: .clear, location: 0.40),
                            .init(color: Color.black.opacity(0.14), location: 0.9),
                            .init(color: Color.black.opacity(0.26), location: 1)],
                    startPoint: .leading, endPoint: .trailing))
            }
            .overlay {
                shape.strokeBorder(LinearGradient(
                    colors: [Color.white.opacity(0.75), Color.black.opacity(0.8)],
                    startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
            }
    }

    private var positionLine: some View {
        VStack(spacing: 0) {
            if tint == nil {
                Rectangle().fill(Color.black.opacity(0.85)).frame(height: 1.75)
                Rectangle().fill(Color.white.opacity(0.35)).frame(height: 0.5)
            } else {
                Rectangle().fill(Color.black.opacity(0.35)).frame(height: 0.5)
                Rectangle().fill(Color.white.opacity(0.92)).frame(height: 1.5)
            }
        }
        .padding(.horizontal, 2)
    }

    private var ridges: some View {
        VStack(spacing: 2.5) {
            ForEach(0..<2, id: \.self) { _ in
                Rectangle().fill(Color.black.opacity(0.16)).frame(height: 0.75)
            }
        }
        .padding(.horizontal, 2)
    }
}

/// dB-scale tick column rendered beside a meter, on its `axis`: a mark at
/// each breakpoint, labelled without signs (Focusrite style: 6 above unity
/// on the gain axis, then 0, 6, 12 … below), right-aligned, and a short
/// tick between marks.
struct DbScale: View {
    var axis: DbAxis = .gain
    @Environment(\.faderHeight) private var height

    private let tickColor = Theme.textSecondary.opacity(0.65)

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(axis.minorTicks, id: \.self) { db in
                Rectangle()
                    .fill(tickColor)
                    .frame(width: 2, height: 1)
                    .offset(y: axis.y(db, height: height))
            }
            ForEach(axis.majorTicks, id: \.self) { db in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(tickColor)
                        .frame(width: 4, height: 1)
                    Spacer(minLength: 2)
                    Text("\(Int(abs(db)))")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize()
                }
                // Centre the row on the tick's line; numbers right-aligned.
                .frame(width: 24, height: 10)
                .offset(y: axis.y(db, height: height) - 5)
            }
        }
        .frame(width: 28, height: height, alignment: .topLeading)
    }
}

/// Vertical peak meter rendered alongside a fader, on the same `axis`.
///
/// The bar follows the live `db` value, coloured by level rather than
/// stretched to the bar's height: green up to -24 dB, blending to solid
/// yellow by -18, then to solid red by -6.
/// Two horizontal ticks hover above it:
///  * `peakDb` (white): recent peak-hold value, decays at the rate set in
///    `MixerState.peakDecayDbPerSecond`.
///  * `maxPeakDb` (red): all-time max since the last "Clear peaks" — useful
///    for gain staging over a long take.
/// Above the track, in the fader knob's inset, sits an over LED that lights
/// red while `maxPeakDb` is at full scale, so a clip stays visible until the
/// max peak is reset.
struct VerticalMeter: View {
    var db: Double
    var peakDb: Double = -.infinity
    var maxPeakDb: Double = -.infinity
    var axis: DbAxis = .gain
    @Environment(\.faderHeight) private var height
    /// Signal level can't exceed 0 dBFS; the gain axis' +6 dB above it is
    /// fader headroom only.
    private let dbMax: Double = 0
    private let dbFloor = DbAxis.meterFloor
    private let width: CGFloat = 8
    private let ledHeight: CGFloat = 4
    /// Room around the well for the LEDs' glow to spill into.
    private let glowRoom: CGFloat = 8

    var body: some View {
        if AppearanceSettings.shared.look == .classic {
            classicMeter
        } else {
            analogMeter
        }
    }

    /// The original meter: a solid bar on a three-colour gradient.
    private var classicMeter: some View {
        let width: CGFloat = 6
        let topY = axis.y(axis.top, height: height)
        let bottomY = axis.y(axis.bottom, height: height)
        let trackHeight = bottomY - topY
        let levelY = axis.y(min(db, dbMax), height: height)
        let fill = db > dbFloor ? bottomY - levelY : 0
        // Gradient stops pinned to levels on the axis, not to the bar.
        let stop = { (db: Double) in (axis.y(db, height: height) - topY) / trackHeight }

        return ZStack(alignment: .top) {
            Rectangle()
                .fill(maxPeakDb >= DbAxis.clip ? Theme.meterHigh : Theme.faderTrack)
                .frame(width: width, height: ledHeight)
                .offset(y: topY - ledHeight - 2)

            Rectangle()
                .fill(Theme.faderTrack)
                .frame(width: width, height: trackHeight)
                .offset(y: topY)

            Rectangle()
                .fill(LinearGradient(
                    stops: [
                        .init(color: Theme.meterHigh, location: 0),
                        .init(color: Theme.meterHigh, location: stop(-6)),
                        .init(color: Theme.meterMid,  location: stop(-12)),
                        .init(color: Theme.meterMid,  location: stop(-18)),
                        .init(color: Theme.meterLow,  location: stop(-24)),
                        .init(color: Theme.meterLow,  location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: width, height: trackHeight)
                .mask(alignment: .bottom) { Rectangle().frame(height: max(0, fill)) }
                .offset(y: topY)

            if peakDb.isFinite && peakDb > dbFloor {
                Rectangle()
                    .fill(Theme.textPrimary)
                    .frame(width: width + 2, height: 1.5)
                    .offset(y: axis.y(min(peakDb, dbMax), height: height) - 0.75)
            }

            if maxPeakDb.isFinite && maxPeakDb > dbFloor {
                Rectangle()
                    .fill(Theme.meterHigh)
                    .frame(width: width + 4, height: 1.5)
                    .offset(y: axis.y(min(maxPeakDb, dbMax), height: height) - 0.75)
            }
        }
        .frame(width: width + 4, height: height, alignment: .top)
    }

    /// LED ladder in a recessed well, drawn by `draw` on a canvas.
    private var analogMeter: some View {
        // Height comes from `\.faderHeight` — no GeometryReader needed.
        // The well spans the full axis, like the fader track beside it.
        let topY = axis.y(axis.top, height: height)
        let bottomY = axis.y(axis.bottom, height: height)
        let trackHeight = bottomY - topY

        return ZStack(alignment: .top) {
            // The well the LEDs sit behind: cut into the panel, almost black.
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(white: 0.025))
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(LinearGradient(
                            colors: [Color.black, Color.white.opacity(0.13)],
                            startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
                .frame(width: width + 2, height: trackHeight + 2)
                .offset(y: topY - 1)

            Canvas { [simple = AppearanceSettings.shared.simpleMeters] context, size in
                draw(in: &context, topY: topY, bottomY: bottomY, simple: simple)
            }
            .frame(width: width + 2 * glowRoom, height: height)
            .allowsHitTesting(false)
        }
        .frame(width: width + 4, height: height, alignment: .top)
    }

    // MARK: - Drawing

    /// The ladder, drawn as a few gradient fills and one path per frame (the
    /// meters redraw ~20 times a second, so no blur filters and no per-segment
    /// level lookups).  Lit segments glow like bulbs behind a dark lens,
    /// brightest down the middle, and throw a little light onto the dead ones
    /// just above the level, which stay faintly visible in their colour.
    private func draw(in context: inout GraphicsContext, topY: CGFloat, bottomY: CGFloat, simple: Bool) {
        let pitch: CGFloat = 2.5
        let gap: CGFloat = 0.6
        let x = glowRoom
        let span = bottomY - topY
        guard span > 0 else { return }
        let ramp = Gradient(stops: Self.stops.reversed().map {
            .init(color: Color(red: $0.rgb.0, green: $0.rgb.1, blue: $0.rgb.2),
                  location: (axis.y($0.db, height: height) - topY) / span)
        })
        let shading = { (ctx: inout GraphicsContext, rect: CGRect, opacity: Double) in
            ctx.opacity = opacity
            ctx.fill(Path(rect), with: .linearGradient(ramp, startPoint: CGPoint(x: 0, y: topY),
                                                       endPoint: CGPoint(x: 0, y: bottomY)))
            ctx.opacity = 1
        }

        let column = CGRect(x: x, y: topY, width: width, height: span)
        let isLive = db.isFinite && db > dbFloor
        let levelY = isLive ? axis.y(min(db, dbMax), height: height) : bottomY

        // Dead lenses all the way up.
        shading(&context, column, 0.11)

        if isLive && levelY < bottomY {
            let lit = CGRect(x: x, y: levelY, width: width, height: bottomY - levelY)
            // How much of the ladder is lit, 0…1.  More lit segments give off
            // more light: the halo gets brighter and the bleed reaches further.
            let litShare = Double(lit.height / span)
            if !simple {
                // Halo: the lit column's colours, widened and faded out
                // sideways and at both ends, so the light spreads softly onto
                // the panel.  The one part that needs a layer, so Simple skips it.
                let reach = 8 + 40 * CGFloat(litShare)
                let halo = CGRect(x: x - glowRoom + 1, y: levelY - reach, width: width + 2 * glowRoom - 2,
                                  height: bottomY - levelY + reach + 4)
                context.drawLayer { layer in
                    shading(&layer, halo, 0.16 + 0.30 * litShare)
                    // The masks overhang the halo so its anti-aliased edges
                    // are covered too, leaving no seam.
                    let mask = Path(halo.insetBy(dx: -2, dy: -2))
                    layer.blendMode = .destinationIn
                    layer.fill(mask, with: .linearGradient(
                        Gradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.5),
                                         .init(color: .clear, location: 1)]),
                        startPoint: CGPoint(x: halo.minX, y: 0), endPoint: CGPoint(x: halo.maxX, y: 0)))
                    layer.fill(mask, with: .linearGradient(
                        Gradient(colors: [.clear, .white]),
                        startPoint: CGPoint(x: 0, y: halo.minY), endPoint: CGPoint(x: 0, y: levelY + 8)))
                    layer.fill(mask, with: .linearGradient(
                        Gradient(colors: [.white, .clear]),
                        startPoint: CGPoint(x: 0, y: bottomY - 6), endPoint: CGPoint(x: 0, y: halo.maxY)))
                }
            }
            // Light spilling onto the dead lenses above the level: a few
            // segments for a quiet signal, far up the ladder for a loud one.
            let bleed = min(14 + span * 0.5 * CGFloat(litShare), levelY - topY)
            let strength = 0.45 + 0.75 * litShare
            let level = Self.color(atDb: db)
            context.fill(Path(CGRect(x: x, y: levelY - bleed, width: width, height: bleed)),
                         with: .linearGradient(Gradient(stops: [
                            .init(color: level.opacity(0), location: 0),
                            .init(color: level.opacity(0.07 * strength), location: 0.3),
                            .init(color: level.opacity(0.14 * strength), location: 0.6),
                            .init(color: level.opacity(0.20 * strength), location: 0.82),
                            .init(color: level.opacity(0.42 * strength), location: 1)]),
                                               startPoint: CGPoint(x: 0, y: levelY - bleed),
                                               endPoint: CGPoint(x: 0, y: levelY)))
            shading(&context, lit, 1)
            // The bright middle of each bulb.
            context.fill(Path(lit.insetBy(dx: width * 0.3, dy: 0)), with: .color(.white.opacity(0.4)))
        }

        // The gaps between segments, cut over everything.
        var gaps = Path()
        var y = bottomY - pitch
        while y > topY {
            gaps.addRect(CGRect(x: x, y: y, width: width, height: gap))
            y -= pitch
        }
        context.fill(gaps, with: .color(Color(white: 0.025)))

        // Clip lamp above the ladder: dim red until the level has clipped.
        let lamp = CGRect(x: x, y: topY - ledHeight - 2.5, width: width, height: ledHeight)
        if maxPeakDb >= DbAxis.clip {
            context.fill(Path(roundedRect: lamp.insetBy(dx: -4, dy: -3), cornerRadius: 4),
                         with: .color(Self.red.opacity(0.12)))
            context.fill(Path(roundedRect: lamp.insetBy(dx: -2, dy: -1.5), cornerRadius: 3),
                         with: .color(Self.red.opacity(0.22)))
            context.fill(Path(roundedRect: lamp, cornerRadius: 1.5), with: .color(Self.red))
            context.fill(Path(roundedRect: lamp.insetBy(dx: width * 0.3, dy: 1), cornerRadius: 0.5),
                         with: .color(.white.opacity(0.5)))
        } else {
            context.fill(Path(roundedRect: lamp, cornerRadius: 1.5), with: .color(Self.red.opacity(0.18)))
        }

        // Peak hold: the segment it sits on, lit bright.  Max peak: a red line.
        if peakDb.isFinite && peakDb > dbFloor {
            let y = axis.y(min(peakDb, dbMax), height: height)
            context.fill(Path(CGRect(x: x, y: y - 1, width: width, height: 2)),
                         with: .color(Self.color(atDb: peakDb)))
            context.fill(Path(CGRect(x: x + width * 0.3, y: y - 1, width: width * 0.4, height: 2)),
                         with: .color(.white.opacity(0.6)))
        }
        if maxPeakDb.isFinite && maxPeakDb > dbFloor && maxPeakDb < DbAxis.clip {
            let y = axis.y(min(maxPeakDb, dbMax), height: height)
            context.fill(Path(CGRect(x: x - 1.5, y: y - 0.5, width: width + 3, height: 1)),
                         with: .color(Self.red.opacity(0.9)))
        }
    }

    // MARK: - Colour

    private static let green: (Double, Double, Double) = (0.30, 0.86, 0.28)
    private static let amber: (Double, Double, Double) = (0.98, 0.80, 0.16)
    private static let orange: (Double, Double, Double) = (1.00, 0.52, 0.10)
    private static let redRGB: (Double, Double, Double) = (1.00, 0.18, 0.15)
    private static let red = Color(red: redRGB.0, green: redRGB.1, blue: redRGB.2)

    /// Warm green up to -18 dB, amber to -6, orange to -2, red above, blending
    /// over a few dB at each change like light through a coloured lens.
    private static let stops: [(db: Double, rgb: (Double, Double, Double))] = [
        (-128, green), (-21, green), (-15, amber), (-8, amber),
        (-5, orange), (-2.5, orange), (-1.5, redRGB), (6, redRGB),
    ]

    static func color(atDb db: Double) -> Color {
        let value = db.isFinite ? db : -128
        for (lower, upper) in zip(stops, stops.dropFirst()) where value <= upper.db {
            let t = max(0, min(1, (value - lower.db) / (upper.db - lower.db)))
            return Color(red: lower.rgb.0 + (upper.rgb.0 - lower.rgb.0) * t,
                         green: lower.rgb.1 + (upper.rgb.1 - lower.rgb.1) * t,
                         blue: lower.rgb.2 + (upper.rgb.2 - lower.rgb.2) * t)
        }
        return red
    }
}
