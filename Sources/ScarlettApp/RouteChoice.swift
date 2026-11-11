import SwiftUI
import ScarlettCore

/// Where a stereo pair of outputs (or of USB capture channels) is fed from, as
/// the routing strips present it.  A pair is chosen as one thing — "Main Mix",
/// "Analog 1+2" — and sets both sides at once, the way mixes and channels pair
/// up in the mixer.  Unlinking a strip splits it into two single-source pickers.
enum RouteChoice: Hashable, Identifiable {
    case off
    /// A linked mix pair: left from its first mix, right from its second.
    case mixPair(Int)
    /// One mono mix feeding both sides.
    case monoMix(MixBus)
    /// A natural stereo pair of sources, named by its left source (Analog 1 → Analog 1+2).
    case sourcePair(MixBus)
    /// Sides that aren't a natural pair, kept as they are.
    case custom(left: MixBus, right: MixBus)

    var id: Self { self }

    /// The sources on the left and right sides.
    var sides: (left: MixBus, right: MixBus) {
        switch self {
        case .off: return (.off, .off)
        case .mixPair(let pair): return (.fromMatrixIndex(pair * 2), .fromMatrixIndex(pair * 2 + 1))
        case .monoMix(let mix): return (mix, mix)
        case .sourcePair(let left): return (left, left.stereoRightPartner ?? left)
        case .custom(let left, let right): return (left, right)
        }
    }

    /// Reads a pair of sides back as a choice.  `mixPairLinked` says whether a
    /// mix pair is one stereo mix; `monoMixes` accepts one mix on both sides.
    static func from(left: MixBus, right: MixBus, mixPairLinked: (Int) -> Bool) -> RouteChoice {
        if left == .off && right == .off { return .off }
        if let li = left.matrixIndex, let ri = right.matrixIndex {
            if li % 2 == 0, ri == li + 1, mixPairLinked(li / 2) { return .mixPair(li / 2) }
            if li == ri, !mixPairLinked(li / 2) { return .monoMix(left) }
        }
        if !left.isMix, left.stereoRightPartner == right { return .sourcePair(left) }
        return .custom(left: left, right: right)
    }

    /// An icon for whether the choice carries one channel or two: a dot for a
    /// mono mix, two dots for a stereo mix or a stereo pair of sources.
    var channelIcon: String? {
        switch self {
        case .monoMix: return "circle.fill"
        case .mixPair, .sourcePair: return "circle.grid.2x1.fill"
        case .off, .custom: return nil
        }
    }

}

/// A run of USB capture channels that carry the same kind of input.
struct CaptureGroup: Identifiable {
    let title: String
    let channels: [Int]
    var id: Int { channels.first ?? 0 }
}

/// A pair of outputs or capture channels with the same two-sided routing.
enum RouteTarget: Hashable {
    /// An output pair, by its label ("Monitor", "Line 3+4", …).
    case output(label: String)
    /// A USB capture pair, 0 = channels 1+2.
    case capture(pair: Int)

    var linkKey: String {
        switch self {
        case .output(let label): return "out.\(label)"
        case .capture(let pair): return "cap.\(pair)"
        }
    }
}

extension MixerState {
    // MARK: - Reading and writing a pair

    private func outputSides(_ label: String) -> (left: UInt16, right: UInt16)? {
        guard let group = physicalOutputGroups.first(where: { $0.label == label }),
              let left = group.outputs.first(where: { $0.isLeft }),
              let right = group.outputs.first(where: { !$0.isLeft }) else { return nil }
        return (left.wValue, right.wValue)
    }

    private func captureChannels(_ pair: Int) -> (left: Int, right: Int)? {
        let count = profile.captureChannelCount + profile.loopbackChannelCount
        guard pair >= 0, pair * 2 + 1 < count else { return nil }
        return (pair * 2, pair * 2 + 1)
    }

    /// The two sources a pair is routed from now.
    func routeSides(_ target: RouteTarget) -> (left: MixBus, right: MixBus) {
        switch target {
        case .output(let label):
            guard let w = outputSides(label) else { return (.off, .off) }
            return (route(forOutput: w.left), route(forOutput: w.right))
        case .capture(let pair):
            guard let c = captureChannels(pair) else { return (.off, .off) }
            return (captureRoutes[c.left] ?? .off, captureRoutes[c.right] ?? .off)
        }
    }

    /// What the factory setup feeds a USB capture channel: its own input.
    private func factoryCaptureSource(channel: Int) -> MixBus? {
        profile.defaultCaptureSources.indices.contains(channel) ? profile.defaultCaptureSources[channel] : nil
    }

    /// Whether a USB capture channel is still on its factory source.
    func isCaptureChannelAtFactory(_ channel: Int) -> Bool {
        factoryCaptureSource(channel: channel).map { captureRoutes[channel] == $0 } ?? true
    }

    /// What a USB capture channel carries from the factory, such as "Analog 3".
    func factoryCaptureName(channel: Int) -> String? {
        factoryCaptureSource(channel: channel).map(routeSideName)
    }

    /// The USB capture channels in the device's own order, grouped by the kind
    /// of input they carry from the factory: "Analog 1–8", "S/PDIF 1–2", "ADAT 1–8".
    var captureChannelGroups: [CaptureGroup] {
        let count = profile.captureChannelCount + profile.loopbackChannelCount
        var groups: [(family: String, channels: [Int], numbers: [Int])] = []
        for channel in 0..<count {
            let name = factoryCaptureSource(channel: channel).map { routeSideName($0) }
            let parts = name?.split(separator: " ").map(String.init) ?? []
            let family = parts.count > 1 ? parts.dropLast().joined(separator: " ")
                : (channel >= profile.captureChannelCount ? "Loopback" : "Other")
            let number = parts.last.flatMap(Int.init) ?? (channel + 1)
            if let last = groups.last, last.family == family {
                groups[groups.count - 1].channels.append(channel)
                groups[groups.count - 1].numbers.append(number)
            } else {
                groups.append((family, [channel], [number]))
            }
        }
        return groups.map { group in
            let first = group.numbers.first!, last = group.numbers.last!
            return CaptureGroup(title: first == last ? "\(group.family) \(first)" : "\(group.family) \(first)–\(last)",
                                channels: group.channels)
        }
    }

    /// True when any USB capture channel is not on its factory source.
    var captureDiffersFromFactory: Bool {
        profile.defaultCaptureSources.enumerated().contains { captureRoutes[$0.offset] != $0.element }
    }

    /// Puts every USB capture channel back on its own input.
    func resetCaptureRoutesToFactory() {
        for (channel, source) in profile.defaultCaptureSources.enumerated() where captureRoutes[channel] != source {
            userSetCaptureRoute(channel: channel, to: source)
        }
    }

    /// Routes a pair's two sides, pushing both to the device.
    func setRouteSides(_ target: RouteTarget, left: MixBus, right: MixBus) {
        switch target {
        case .output(let label):
            guard let w = outputSides(label) else { return }
            userSetRoute(wValue: w.left, to: left)
            userSetRoute(wValue: w.right, to: right)
        case .capture(let pair):
            guard let c = captureChannels(pair) else { return }
            userSetCaptureRoute(channel: c.left, to: left)
            userSetCaptureRoute(channel: c.right, to: right)
        }
    }

    // MARK: - Choices

    func routeChoice(for target: RouteTarget) -> RouteChoice {
        let sides = routeSides(target)
        return RouteChoice.from(left: sides.left, right: sides.right, mixPairLinked: isMixPairLinked)
    }

    /// Routes both sides of a pair from one choice.  A `.custom` choice only
    /// restates what's already set.
    func userSetRouteChoice(_ choice: RouteChoice, for target: RouteTarget) {
        let sides = choice.sides
        setRouteSides(target, left: sides.left, right: sides.right)
    }

    /// What a linked strip can pick: Off, the mixes (a linked pair as one, an
    /// unlinked pair as two mono mixes), and every natural pair of sources.
    var routeChoiceOptions: [RouteChoice] {
        var options: [RouteChoice] = [.off]
        for pair in 0..<stereoPairCount {
            if isMixPairLinked(pair) {
                options.append(.mixPair(pair))
            } else {
                options.append(.monoMix(.fromMatrixIndex(pair * 2)))
                options.append(.monoMix(.fromMatrixIndex(pair * 2 + 1)))
            }
        }
        let available = Set(routerPickerOptions)
        for bus in routerPickerOptions where !bus.isMix {
            if let partner = bus.stereoRightPartner, available.contains(partner) {
                options.append(.sourcePair(bus))
            }
        }
        return options
    }

    // MARK: - Names and colours

    /// A mix as the user knows it: its own name, else "Mix M3" ("Mix M1+M2" for
    /// a linked pair, which is one tab).
    func mixDisplayName(forPair pair: Int) -> String {
        let name = mixName(forTab: pair * 2)
        return name.isEmpty ? "Mix M\(pair * 2 + 1)+M\(pair * 2 + 2)" : name
    }

    func mixDisplayName(forBus bus: MixBus) -> String {
        guard let index = bus.matrixIndex else { return bus.displayName }
        if isMixPairLinked(index / 2) { return mixDisplayName(forPair: index / 2) }
        let name = mixName(forTab: index)
        return name.isEmpty ? bus.displayName : name
    }

    /// A source's name in a picker: mixes by the user's name for them.
    func routeSourceName(_ bus: MixBus) -> String {
        bus.isMix ? mixDisplayName(forBus: bus) : bus.displayName
    }

    /// A source as one side of a pair is routed from it: a half of a linked mix
    /// pair is "Main Mix L" or "Main Mix R", since the name alone would not say which.
    func routeSideName(_ bus: MixBus) -> String {
        guard let index = bus.matrixIndex, isMixPairLinked(index / 2) else { return routeSourceName(bus) }
        return "\(mixDisplayName(forPair: index / 2)) \(index % 2 == 0 ? "L" : "R")"
    }

    /// Every source one side can take, in the groups the side picker shows.
    var routeSideGroups: [(title: String, buses: [MixBus])] {
        let all = routerPickerOptions.filter { $0 != .off }
        return [
            ("Mixes", all.filter(\.isMix)),
            ("Inputs", all.filter { !$0.isMix && !$0.displayName.hasPrefix("DAW") }),
            ("DAW", all.filter { $0.displayName.hasPrefix("DAW") }),
        ].filter { !$0.buses.isEmpty }
    }

    func routeChoiceName(_ choice: RouteChoice) -> String {
        switch choice {
        case .off: return "Off"
        case .mixPair(let pair): return mixDisplayName(forPair: pair)
        case .monoMix(let mix): return mixDisplayName(forBus: mix)
        case .sourcePair(let left):
            let sides = choice.sides
            let number = sides.right.displayName.split(separator: " ").last.map(String.init) ?? sides.right.displayName
            return "\(left.displayName)+\(number)"
        case .custom(let left, let right):
            return "\(routeSideName(left)) / \(routeSideName(right))"
        }
    }

    /// The colour a source stands for: a mix's own colour (the default accent
    /// if it has none), else its input-type colour.  Nil for Off.
    func routeColor(_ bus: MixBus) -> Color? {
        if bus == .off { return nil }
        if let index = bus.matrixIndex {
            return Color(hex: mixColorHex(forTab: mixTabKey(forBus: index))) ?? Theme.tabOutline
        }
        return SignalSource(rawValue: bus.rawValue)?.accentColor
    }

    /// The colour of a pair's routing, from its left side.
    func routeColor(for target: RouteTarget) -> Color? {
        routeColor(routeSides(target).left)
    }

    // MARK: - Linking

    func isRoutePairLinked(_ target: RouteTarget) -> Bool {
        !unlinkedRoutePairs.contains(target.linkKey)
    }

    /// The stereo choice the left side leads to: its natural partner on the
    /// right, or if it has none the sides stay as they are.
    private func naturalChoice(left: MixBus, right: MixBus) -> RouteChoice {
        if left == .off { return .off }
        if let index = left.matrixIndex {
            if isMixPairLinked(index / 2) {
                return index % 2 == 0 ? .mixPair(index / 2) : .custom(left: left, right: right)
            }
            return .monoMix(left)
        }
        return left.stereoRightPartner != nil ? .sourcePair(left) : .custom(left: left, right: right)
    }

    /// Joins a pair's sides into one stereo choice, or splits them.  Joining
    /// takes the left side as the lead.
    func userSetRoutePairLinked(_ target: RouteTarget, linked: Bool) {
        guard linked != isRoutePairLinked(target) else { return }
        if linked {
            unlinkedRoutePairs.remove(target.linkKey)
            let sides = routeSides(target)
            userSetRouteChoice(naturalChoice(left: sides.left, right: sides.right), for: target)
        } else {
            unlinkedRoutePairs.insert(target.linkKey)
        }
        saveRouteLinks()
    }
}
