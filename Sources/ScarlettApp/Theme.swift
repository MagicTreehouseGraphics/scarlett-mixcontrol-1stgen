import SwiftUI
import AppKit
import ScarlettCore

enum AppInfo {
    /// Read from the bundle's `CFBundleShortVersionString` (set by
    /// `scripts/make-app.sh` from the git tag) so the displayed version can't
    /// drift from the actual release. Falls back to "dev" when run without a
    /// bundle (e.g. `swift run`).
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    /// `version` for display: "v0.2.1", but plain "dev" rather than "vdev".
    static var displayVersion: String {
        version.first?.isNumber == true ? "v\(version)" : version
    }
    static let repositoryURL = URL(string: "https://github.com/MarecekW/scarlett-mixcontrol-1stgen")!
}

/// Pixel-exact section heights shared by every strip in the mixer (channel,
/// DAW, output). Keeping them in one place makes alignment trivial — every
/// strip uses the same `.frame(height:)` on each section so their bottoms
/// line up regardless of what content the section actually shows.
enum StripLayout {
    static let width:               CGFloat = 100
    /// A stereo-linked pair's card: just wide enough to stand out from a
    /// single strip and fit its two meters and side-by-side input switches.
    static let stereoWidth:         CGFloat = width + 36
    static let headerHeight:        CGFloat = 50
    static let switchRowHeight:     CGFloat = 22
    static let panRowHeight:        CGFloat = 30
    /// Fader / meter column height: fills the mixer page's spare height
    /// (see `MixerPaneView`) within these bounds; `faderHeight` is the
    /// default before the page is measured.
    static let faderHeight:         CGFloat = 220
    static let faderHeightRange:    ClosedRange<CGFloat> = 180...420
    static let peakReadoutHeight:   CGFloat = 18
    /// Bottom controls = single 22-pt row, contents centered.
    static let controlsHeight:      CGFloat = 22
    static let vSpacing:            CGFloat = 6
    /// Padding inside a strip card, above and below its sections.
    static let cardPaddingV:        CGFloat = 10
    /// How much taller the pinned DAW / output cards are than the channel
    /// cards at top and bottom, so they read as fixed outputs.  Channel
    /// strips sit this far in from the row's edges, which also keeps the
    /// scroll view from clipping their border, so every strip's sections
    /// (and 0 dB line) stay level.
    static let pinnedOutset:        CGFloat = 6
}

/// Height of every strip's fader / meter column, set once for the whole
/// mixer so all strips match.  Written as a classic EnvironmentKey instead of
/// `@Entry` so the package also builds with the Command Line Tools toolchain,
/// which ships without Xcode's SwiftUIMacros plugin.
private struct FaderHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = StripLayout.faderHeight
}

private struct PageSpareHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct MixGlowColorKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var faderHeight: CGFloat {
        get { self[FaderHeightKey.self] }
        set { self[FaderHeightKey.self] = newValue }
    }

    /// How much taller the window is than the mixer page, once the faders have
    /// grown as far as they go.  Lets the outputs panel reach the bottom.
    var pageSpareHeight: CGFloat {
        get { self[PageSpareHeightKey.self] }
        set { self[PageSpareHeightKey.self] = newValue }
    }

    /// The open mix's colour, which the cards in its panel glow with.
    var mixGlowColor: Color? {
        get { self[MixGlowColorKey.self] }
        set { self[MixGlowColorKey.self] = newValue }
    }
}

// Centralised palette to keep the Control-2-style dark look consistent.

enum Theme {
    /// Main window background (~#171717).
    static let background = Color(white: 0.09)

    /// Card / panel background — the strip / section surfaces (~#222).
    static let panel = Color(white: 0.14)

    /// The mixer panel under the mix tabs, and the selected tab that joins it
    /// (~#1d1d1d: between the window and the strip cards).
    static let tabPanel = Color(white: 0.115)

    /// Outline of the mixer panel and the selected mix tab.
    static let tabOutline = muteActive

    /// Slightly lifted surface — used for hover / focused / selected (~#2c2c2c).
    static let panelRaised = Color(white: 0.18)

    /// Subtle divider line.
    static let divider = Color(white: 0.22)

    /// Primary text.
    static let textPrimary = Color(white: 0.95)

    /// Secondary / caption text.
    static let textSecondary = Color(white: 0.55)

    /// Channel underline for analog hardware inputs.
    static let accentAnalog = Color(red: 0.95, green: 0.35, blue: 0.30)

    /// Channel underline for line inputs.
    static let accentInput = meterLow

    /// Channel underline for ADAT.
    static let accentDigital = Color(red: 0.62, green: 0.45, blue: 0.95)

    /// Channel underline for DAW / playback / PCM.
    static let accentPlayback = Color(red: 0.30, green: 0.65, blue: 1.00)

    /// Channel underline for mix-bus loops and other.
    static let accentOther = Color(white: 0.40)

    /// Mute button when engaged (Control 2 uses blue, not red).
    static let muteActive = Color(red: 0.25, green: 0.50, blue: 0.95)

    /// Solo button when engaged.
    static let soloActive = Color(red: 0.95, green: 0.70, blue: 0.25)

    /// Fader knob highlight.
    static let faderKnob = Color(white: 0.78)
    static let faderKnobShadow = Color.black.opacity(0.5)
    static let faderTrack = Color(white: 0.06)
    static let faderTrackFill = Color(white: 0.32)
    /// Background of numeric readout fields (fader level, max peak).
    static let readoutField = Color(white: 0.11)

    /// Meter gradient stops.
    static let meterLow = Color(red: 0.30, green: 0.80, blue: 0.40)
    static let meterMid = Color(red: 0.95, green: 0.80, blue: 0.20)
    static let meterHigh = Color(red: 0.95, green: 0.30, blue: 0.25)

    /// Status colours for confirmations ("Saved"), failures and destructive
    /// actions — the meter's green and red.
    static let success = meterLow
    static let failure = meterHigh
    /// Opacity of a status colour used as a pill fill behind status text.
    static let statusFillOpacity: Double = 0.25
}

extension SignalSource {
    /// Color used for the strip's channel underline in the mixer.
    @MainActor var accentColor: Color {
        // The classic look marks every hardware input the same red.
        if AppearanceSettings.shared.look == .classic {
            switch self {
            case .off: return Theme.accentOther
            case _ where displayName.hasPrefix("DAW"): return Theme.accentPlayback
            default: return Theme.accentAnalog
            }
        }
        switch self {
        case .daw1, .daw2, .daw3, .daw4, .daw5, .daw6,
             .daw7, .daw8, .daw9, .daw10, .daw11, .daw12,
             .daw13, .daw14, .daw15, .daw16, .daw17, .daw18, .daw19, .daw20:
            return Theme.accentPlayback
        case .analog1, .analog2, .analog3, .analog4,
             .analog5, .analog6, .analog7, .analog8:
            return Theme.accentInput
        case .spdif1, .spdif2:
            return Theme.soloActive
        case .adat1, .adat2, .adat3, .adat4, .adat5, .adat6, .adat7, .adat8:
            return Theme.accentDigital
        case .off:
            return Theme.accentOther
        }
    }
}

extension Color {
    /// A colour from "#RRGGBB"; nil for anything else, including "".
    init?(hex: String) {
        guard hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xff) / 255,
                  green: Double((value >> 8) & 0xff) / 255,
                  blue: Double(value & 0xff) / 255,
                  opacity: 1)
    }

    /// "#RRGGBB" in sRGB.
    var hexString: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}
