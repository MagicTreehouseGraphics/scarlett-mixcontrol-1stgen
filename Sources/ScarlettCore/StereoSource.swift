import Foundation

/// Two adjacent sources that make a stereo pair: DAW 1+2, Analog 3+4, S/PDIF
/// 1+2, ADAT 5+6.  Pairs always start on an odd source, so there is no DAW 2+3.
public struct StereoSourcePair: Hashable, Identifiable, Sendable {
    public let left: SignalSource
    public let right: SignalSource

    public init(left: SignalSource, right: SignalSource) {
        self.left = left
        self.right = right
    }

    public var id: String { "\(left.rawValue)-\(right.rawValue)" }

    /// "DAW 1+2", "S/PDIF 1+2".
    public var name: String {
        let rightNumber = right.displayName.split(separator: " ").last.map(String.init) ?? right.displayName
        return "\(left.displayName)+\(rightNumber)"
    }
}

extension SignalSource {
    private static let stereoFamilies: [[SignalSource]] = [
        [.daw1, .daw2, .daw3, .daw4, .daw5, .daw6, .daw7, .daw8, .daw9, .daw10,
         .daw11, .daw12, .daw13, .daw14, .daw15, .daw16, .daw17, .daw18, .daw19, .daw20],
        [.analog1, .analog2, .analog3, .analog4, .analog5, .analog6, .analog7, .analog8],
        [.spdif1, .spdif2],
        [.adat1, .adat2, .adat3, .adat4, .adat5, .adat6, .adat7, .adat8],
    ]

    /// The source to the right of this one in a stereo pair, when this is the
    /// left side of one (DAW 1 → DAW 2, but DAW 2 → nil).
    public var stereoRightPartner: SignalSource? {
        for family in Self.stereoFamilies {
            if let index = family.firstIndex(of: self) {
                return index.isMultiple(of: 2) && index + 1 < family.count ? family[index + 1] : nil
            }
        }
        return nil
    }

    /// The stereo pairs whose two sources are both in `available`, in the
    /// order their left sources appear there.
    public static func stereoPairs(in available: [SignalSource]) -> [StereoSourcePair] {
        available.compactMap { source in
            guard let right = source.stereoRightPartner, available.contains(right) else { return nil }
            return StereoSourcePair(left: source, right: right)
        }
    }
}

extension MixBus {
    /// True for the matrix mixes M1…M8.
    public var isMix: Bool { matrixIndex != nil }

    /// The bus to the right of this one in a stereo pair of sources (DAW 1 →
    /// DAW 2), when this is the left side of one.  Mixes pair up through
    /// `stereoPairIndex` instead.
    public var stereoRightPartner: MixBus? {
        guard !isMix,
              let partner = SignalSource(rawValue: rawValue)?.stereoRightPartner else { return nil }
        return MixBus(rawValue: partner.rawValue)
    }
}
