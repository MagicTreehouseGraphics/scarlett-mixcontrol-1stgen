import Foundation

/// Gain math for the matrix mixer's level + pan model, kept free of device
/// and UI state so it can be unit-tested.
public enum MixGain {
    /// The lowest gain the matrix accepts ("off").
    public static let floorDb: Double = -128

    /// Convert a (level, pan, side) triple into the per-cell gain that the
    /// device's matrix mixer will use.  "Amp-style" pan law: at center both
    /// sides get the full level; panning hard to one side reduces the other
    /// to -∞ without attenuating the chosen side.
    public static func cellGain(level: Double, pan: Double, isLeft: Bool) -> Double {
        let clamped = max(-1, min(1, pan))
        let factor: Double = isLeft
            ? (clamped <= 0 ? 1.0 : 1.0 - clamped)
            : (clamped >= 0 ? 1.0 : 1.0 + clamped)
        if factor <= 0.0001 { return floorDb }
        return level + 20 * log10(factor)
    }

    /// Inverse of `cellGain` — recover a (level, pan) pair from the device's
    /// current L and R cell gains.  Used to migrate the matrix on launch.
    public static func deriveLevelAndPan(left: Double, right: Double) -> (level: Double, pan: Double) {
        let safeL = left.isFinite  ? max(floorDb, left)  : floorDb
        let safeR = right.isFinite ? max(floorDb, right) : floorDb
        if abs(safeL - safeR) < 0.5 {
            return (max(safeL, safeR), 0)
        }
        if safeL > safeR {
            let level = safeL
            // pan in [-1, 0]: gain_R = level + 20·log10(1 + pan)
            let pan = pow(10, (safeR - level) / 20) - 1
            return (level, max(-1, pan))
        } else {
            let level = safeR
            // pan in (0, 1]: gain_L = level + 20·log10(1 - pan)
            let pan = 1 - pow(10, (safeL - level) / 20)
            return (level, min(1, pan))
        }
    }

    /// The two independent levels an unlinked mix pair starts from: exactly
    /// the gains the linked pair was sending, so unlinking changes nothing
    /// audible.
    public static func unlinkedLevels(level: Double, pan: Double) -> (left: Double, right: Double) {
        (max(floorDb, cellGain(level: level, pan: pan, isLeft: true)),
         max(floorDb, cellGain(level: level, pan: pan, isLeft: false)))
    }
}
