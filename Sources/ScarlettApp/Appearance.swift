import SwiftUI
import Foundation

/// Which design the mixer is drawn in.
enum MixerLook: String, CaseIterable, Identifiable {
    /// The app's original design: flat faders, solid meters, plain buttons.
    case classic
    /// Hardware-style faders and caps, and glowing LED-ladder meters.
    case analog

    var id: Self { self }
    var title: String { self == .classic ? "Classic" : "Analog" }
}

/// How much glow the analog meters draw.
enum MeterGlow: String, CaseIterable, Identifiable {
    /// Full, except Simple while the Mac is in Low Power Mode.
    case automatic
    case full
    /// No soft halo beside the meters, which skips the one drawing layer they use.
    case simple

    var id: Self { self }
    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .full: return "Full"
        case .simple: return "Simple"
        }
    }
}

/// The mixer's look, shared by every strip and saved between launches.
@MainActor
@Observable
final class AppearanceSettings {
    static let shared = AppearanceSettings()

    private static let lookKey = "scarlett.app.mixerLook.v1"
    private static let meterGlowKey = "scarlett.app.meterGlow.v1"

    var look: MixerLook {
        didSet { UserDefaults.standard.set(look.rawValue, forKey: Self.lookKey) }
    }

    var meterGlow: MeterGlow {
        didSet { UserDefaults.standard.set(meterGlow.rawValue, forKey: Self.meterGlowKey) }
    }

    /// Whether macOS Low Power Mode is on, kept up to date while the app runs.
    private(set) var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// Whether the meters skip their halo right now.
    var simpleMeters: Bool {
        meterGlow == .simple || (meterGlow == .automatic && lowPowerMode)
    }

    @ObservationIgnored private var powerObserver: NSObjectProtocol?

    private init() {
        let defaults = UserDefaults.standard
        look = defaults.string(forKey: Self.lookKey).flatMap(MixerLook.init(rawValue:)) ?? .classic
        meterGlow = defaults.string(forKey: Self.meterGlowKey).flatMap(MeterGlow.init(rawValue:)) ?? .automatic
        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }
}
