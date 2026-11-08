import SwiftUI

// Shared controls: the pill button face used across the app, the
// click-confirming `FeedbackButton`, and the themed menu picker.

// MARK: - Pill

/// Pill sizes, one per context so buttons of a kind match.
enum PillSize {
    /// Preset rows and the save field.
    case row
    /// Mixer toolbar.
    case toolbar
    /// Centred cards (connection, first launch).
    case card

    var iconFont: Font {
        .system(size: self == .card ? 11 : 10, weight: .semibold)
    }
    var titleFont: Font {
        .system(size: self == .card ? 12 : 11, weight: .semibold)
    }
    var horizontalPadding: CGFloat {
        switch self {
        case .row:     return 12
        case .toolbar: return 10
        case .card:    return 14
        }
    }
    var verticalPadding: CGFloat {
        switch self {
        case .row:     return 5
        case .toolbar: return 6
        case .card:    return 7
        }
    }
    var cornerRadius: CGFloat {
        switch self {
        case .row:     return 3
        case .toolbar: return 4
        case .card:    return 5
        }
    }
}

extension View {
    /// Padding, fill and rounded clip of a pill.  For pills whose content
    /// isn't just icon + title (e.g. the master mute's crossfading icon).
    func pillChrome(_ size: PillSize, fill: Color, foreground: Color,
                    fillsWidth: Bool = false) -> some View {
        padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .background(fill)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius))
    }
}

/// The app's button face: optional SF Symbol + title on a rounded fill.
/// Use as a `Button` label together with `PillButtonStyle`.
struct Pill: View {
    var icon: String? = nil
    let title: String
    /// Extra symbol after the title (the chevron on a menu pill).
    var trailingIcon: String? = nil
    var fill: Color = Theme.panelRaised
    var foreground: Color = Theme.textSecondary
    var size: PillSize = .toolbar
    /// Stretch to the proposed width — set when stacking pills of
    /// different lengths so they share the widest one's width.
    var fillsWidth = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(size.iconFont)
            }
            Text(title).font(size.titleFont).lineLimit(1)
            if let trailingIcon {
                Image(systemName: trailingIcon).font(.system(size: 8, weight: .semibold))
            }
        }
        .pillChrome(size, fill: fill, foreground: foreground, fillsWidth: fillsWidth)
    }
}

/// Plain button behaviour for pill labels: no system chrome, dims while
/// pressed and when disabled.
struct PillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.5)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
}

// MARK: - Click feedback

/// Outcome a `FeedbackButton` shows after its action runs.
enum FeedbackPhase: CaseIterable {
    case idle, done, failed
}

/// A button that briefly swaps its label for a confirmation ("Saved",
/// "Cleared") or a failure, then reverts.  Every phase's label is laid out
/// at once and only the current one is visible, so the button keeps the
/// width of its widest label and nothing around it shifts.
struct FeedbackButton<Content: View>: View {
    /// Returns true on success.  Async so a USB write can report back.
    let action: () async -> Bool
    @ViewBuilder let label: (FeedbackPhase) -> Content
    @State private var phase: FeedbackPhase = .idle
    /// Clicks are ignored while the action runs, so a double-click can't
    /// e.g. queue two flash writes.
    @State private var running = false
    /// Bumped per click so an older click's timer can't reset a newer one.
    @State private var clickID = 0

    var body: some View {
        Button {
            guard !running else { return }
            running = true
            clickID += 1
            let id = clickID
            Task {
                let ok = await action()
                running = false
                phase = ok ? .done : .failed
                try? await Task.sleep(for: .seconds(1.5))
                if clickID == id { phase = .idle }
            }
        } label: {
            ZStack {
                ForEach(FeedbackPhase.allCases, id: \.self) { p in
                    label(p)
                        .opacity(p == phase ? 1 : 0)
                        .accessibilityHidden(p != phase)
                }
            }
            .animation(.easeOut(duration: 0.15), value: phase)
        }
    }
}

/// Pill face for a `FeedbackButton`: the idle pill, then a green
/// "✓ <done>" or a red "✗ Failed" at the same width.  Pair with
/// `.buttonStyle(.pill)` and `.fixedSize()`.
struct FeedbackPill: View {
    let phase: FeedbackPhase
    var icon: String? = nil
    let title: String
    let doneTitle: String
    var fill: Color = Theme.panelRaised
    var foreground: Color = Theme.textSecondary
    var size: PillSize = .toolbar

    var body: some View {
        switch phase {
        case .idle:
            Pill(icon: icon, title: title, fill: fill, foreground: foreground,
                 size: size, fillsWidth: true)
        case .done:
            Pill(icon: "checkmark", title: doneTitle,
                 fill: Theme.success.opacity(Theme.statusFillOpacity),
                 foreground: Theme.success, size: size, fillsWidth: true)
        case .failed:
            Pill(icon: "xmark", title: "Failed",
                 fill: Theme.failure.opacity(Theme.statusFillOpacity),
                 foreground: Theme.failure, size: size, fillsWidth: true)
        }
    }
}

/// Label for a system-styled `FeedbackButton` (bordered macOS buttons).
struct FeedbackLabel: View {
    let phase: FeedbackPhase
    let title: String
    let doneTitle: String

    var body: some View {
        switch phase {
        case .idle:   Text(title)
        case .done:   Label(doneTitle, systemImage: "checkmark").foregroundStyle(Theme.success)
        case .failed: Label("Failed", systemImage: "xmark").foregroundStyle(Theme.failure)
        }
    }
}

// MARK: - Menu picker

/// A drop-in replacement for SwiftUI's `Picker(.menu)` that always renders
/// with theme-controlled colors. `Picker(.menu)` on macOS is backed by
/// `NSPopUpButton` and stubbornly ignores `.foregroundStyle` /
/// `NSAppearance` overrides in some configurations, leaving us with dark
/// text on dark panels. `Menu` gives us full label control.
struct ThemedMenuPicker<T: Hashable & Identifiable>: View {
    let options: [T]
    let displayName: (T) -> String
    @Binding var selection: T
    var width: CGFloat? = nil
    var horizontalPadding: CGFloat = 6
    var verticalPadding: CGFloat = 3
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Menu {
            ForEach(options) { item in
                Button(displayName(item)) { selection = item }
            }
        } label: {
            HStack(spacing: 4) {
                Text(displayName(selection))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(width: width)
            .background(Theme.panelRaised)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: width == nil, vertical: true)
        .opacity(isEnabled ? 1.0 : 0.4)
    }
}

// MARK: - Mute all

/// Toggles the master mute — in the mixer's toolbar and the menu bar
/// panel.  The label morphs between "Mute all" and "Master muted".  The
/// toggle runs inside `withAnimation` so the surrounding row re-lays out in
/// step (width grows, neighbours slide); the icon rides the leading edge
/// and crossfades in place, and the two labels are separate views that
/// crossfade.
@MainActor
struct MasterMuteButton: View {
    @Bindable var state: MixerState

    var body: some View {
        let muted = state.masterMuted
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                state.userSetMasterMute(!muted)
            }
        } label: {
            HStack(spacing: 5) {
                // One fixed slot that travels with the button's leading edge;
                // the two icons crossfade inside it.
                ZStack {
                    Image(systemName: "speaker.wave.2").opacity(muted ? 0 : 1)
                    Image(systemName: "speaker.slash.fill").opacity(muted ? 1 : 0)
                }
                .font(PillSize.toolbar.iconFont)
                .frame(width: 14)
                Group {
                    if muted {
                        Text("Master muted")
                    } else {
                        Text("Mute all")
                    }
                }
                .font(PillSize.toolbar.titleFont)
                .lineLimit(1)
                .transition(.opacity)
            }
            .pillChrome(.toolbar,
                        fill: muted ? Theme.muteActive : Theme.panelRaised,
                        foreground: muted ? .white : Theme.textSecondary)
        }
        .buttonStyle(.pill)
        .fixedSize()
        .help("Mute every output bus on the device.")
    }
}

// MARK: - Update dot

/// A red dot on a Settings button while a newer release is available — the
/// details are in Settings → About.
struct UpdateDot: ViewModifier {
    private var updates = UpdateChecker.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if updates.availableUpdate != nil {
                Circle()
                    .fill(Theme.failure)
                    .frame(width: 6, height: 6)
                    .offset(x: 2, y: -2)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func updateDot() -> some View { modifier(UpdateDot()) }
}

// MARK: - Analog key look

/// A plain, square-edged key: a lit one fills with its colour and glows
/// softly, an unlit one is a dark grey cap with a fine edge.  Drawn behind the
/// content, so the caller still sets the text, size and foreground colour.
struct AnalogKey: ViewModifier {
    let active: Bool
    let color: Color
    var cornerRadius: CGFloat = 3

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        if AppearanceSettings.shared.look == .classic {
            content
                .background(active ? color : Theme.panelRaised)
                .clipShape(shape)
        } else {
            analog(content, shape: shape)
        }
    }

    private func analog(_ content: Content, shape: RoundedRectangle) -> some View {
        content
            .background {
                shape.fill(active ? color : Color(white: 0.16))
                    .overlay {
                        shape.strokeBorder(Color.white.opacity(active ? 0.25 : 0.09), lineWidth: 0.75)
                    }
            }
            .shadow(color: active ? color.opacity(0.5) : .clear, radius: 3)
    }
}

extension View {
    func analogKey(active: Bool, color: Color, cornerRadius: CGFloat = 3) -> some View {
        modifier(AnalogKey(active: active, color: color, cornerRadius: cornerRadius))
    }
}

/// Presses an `AnalogKey` in: a pixel down and a touch darker.  In the
/// classic look it only dims, as a plain button does.
struct AnalogKeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let analog = AppearanceSettings.shared.look == .analog
        configuration.label
            .offset(y: analog && configuration.isPressed ? 1 : 0)
            .brightness(analog && configuration.isPressed ? -0.1 : 0)
            .opacity(!analog && configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Raised surfaces

extension Theme {
    /// The raised faceplate the analog look's cards and panels are lit from:
    /// lighter at the top, falling into shadow at the bottom.
    static let faceTop = Color(white: 0.215)
    static let faceMid = Color(white: 0.158)
    static let faceBottom = Color(white: 0.105)
}

/// A plate standing proud of the window: a gradient lit from above, a bright
/// bevel along the top and a dark one underneath, and a soft shadow cast
/// onto what's behind it.
struct RaisedFace<S: InsettableShape>: View {
    let shape: S
    /// A panel is a flatter, larger plate than a card, with a deeper shadow.
    var panel = false

    var body: some View {
        shape
            .fill(LinearGradient(
                stops: [.init(color: Theme.faceTop, location: 0),
                        .init(color: Theme.faceMid, location: panel ? 0.35 : 0.5),
                        .init(color: Theme.faceBottom, location: 1)],
                startPoint: .top, endPoint: .bottom))
            .overlay {
                // Light catching the top of the plate, and its lower edge
                // rolling away into shadow.
                shape.fill(LinearGradient(
                    stops: [.init(color: Color.white.opacity(0.12), location: 0),
                            .init(color: Color.clear, location: 0.10),
                            .init(color: Color.clear, location: 0.88),
                            .init(color: Color.black.opacity(0.30), location: 1)],
                    startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                // A bevel: lit along the top and left, dark along the bottom.
                shape.strokeBorder(LinearGradient(
                    stops: [.init(color: Color.white.opacity(0.36), location: 0),
                            .init(color: Color.white.opacity(0.10), location: 0.3),
                            .init(color: Color.black.opacity(0.75), location: 1)],
                    startPoint: .top, endPoint: .bottom), lineWidth: 1.25)
            }
            .shadow(color: Color.black.opacity(panel ? 0.65 : 0.6), radius: panel ? 8 : 5, y: panel ? 5 : 3)
    }
}

extension View {
    /// A strip's card: flat in the classic look, a raised plate in the analog one.
    @ViewBuilder
    func stripCard() -> some View {
        if AppearanceSettings.shared.look == .classic {
            background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            background { RaisedFace(shape: RoundedRectangle(cornerRadius: 6)) }
        }
    }
}
