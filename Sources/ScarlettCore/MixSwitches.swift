import Foundation

/// Mute and solo are kept per channel per mix bus.  Saves from before that
/// stored one switch per channel, which meant "in every mix"; these convert
/// between the two so old saves still load and old versions can still read
/// new ones.
public enum MixSwitches {
    /// One switch per channel: on only where it is on in every mix.
    public static func channelWide(_ rows: [[Bool]]) -> [Bool] {
        rows.map { !$0.isEmpty && $0.allSatisfy { $0 } }
    }

    /// The per-mix switches to save beside `channelWide`, or nil when every
    /// channel has the same setting on all its mixes (nothing more to say).
    public static func perBus(_ rows: [[Bool]]) -> [[Bool]]? {
        rows.allSatisfy { row in row.allSatisfy { $0 == row.first } } ? nil : rows
    }

    /// A per-channel switch spread over every mix.
    public static func expanded(_ perChannel: [Bool], buses: Int) -> [[Bool]] {
        perChannel.map { Array(repeating: $0, count: buses) }
    }

    /// Saved switches as `rows` × `buses`: the per-mix ones if they fit, else
    /// the per-channel ones spread over every mix, else all off.
    public static func adopted(perBus: [[Bool]]?, perChannel: [Bool], rows: Int, buses: Int) -> [[Bool]] {
        if let perBus, perBus.count == rows, perBus.allSatisfy({ $0.count == buses }) { return perBus }
        let channels = perChannel.count == rows ? perChannel : Array(repeating: false, count: rows)
        return expanded(channels, buses: buses)
    }
}
