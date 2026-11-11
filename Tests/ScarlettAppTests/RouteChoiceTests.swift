import XCTest
import SwiftUI
import ScarlettCore
@testable import ScarlettApp

/// Routing treats an output pair (or capture pair) as one stereo choice, like
/// the mixer's pairs.  Run against the 18i20's layout.
@MainActor
final class RouteChoiceTests: XCTestCase {
    private func makeState() -> MixerState { MixerState(autoConnect: false, profile: .scarlett18i20) }

    private func label(_ s: MixerState, _ index: Int) -> String { s.physicalOutputGroups[index].label }

    // MARK: Reading

    func testNothingRoutedIsOff() {
        let s = makeState()
        XCTAssertEqual(s.routeChoice(for: .output(label: label(s, 1))), .off)
    }

    func testAMixPairOnTheTwoSidesIsOneChoice() {
        let s = makeState()
        let target = RouteTarget.output(label: label(s, 0))
        s.setRouteSides(target, left: .m1, right: .m2)
        XCTAssertEqual(s.routeChoice(for: target), .mixPair(0))
    }

    func testMixesInTheWrongOrderOrFromDifferentPairsAreCustom() {
        let s = makeState()
        let target = RouteTarget.output(label: label(s, 0))
        s.setRouteSides(target, left: .m2, right: .m1)
        XCTAssertEqual(s.routeChoice(for: target), .custom(left: .m2, right: .m1))
        s.setRouteSides(target, left: .m1, right: .m4)
        XCTAssertEqual(s.routeChoice(for: target), .custom(left: .m1, right: .m4))
    }

    func testAMonoMixOnBothSidesOnlyCountsWhenItsPairIsSplit() {
        let s = makeState()
        let target = RouteTarget.output(label: label(s, 0))
        s.setRouteSides(target, left: .m3, right: .m3)
        XCTAssertEqual(s.routeChoice(for: target), .custom(left: .m3, right: .m3))   // M3+M4 is still linked
        s.userSetMixPairLinked(1, linked: false)
        XCTAssertEqual(s.routeChoice(for: target), .monoMix(.m3))
    }

    func testNaturalPairsOfSourcesAreOneChoice() {
        let s = makeState()
        let target = RouteTarget.output(label: label(s, 1))
        s.setRouteSides(target, left: .analog1, right: .analog2)
        XCTAssertEqual(s.routeChoice(for: target), .sourcePair(.analog1))
        s.setRouteSides(target, left: .daw3, right: .daw4)
        XCTAssertEqual(s.routeChoice(for: target), .sourcePair(.daw3))
        s.setRouteSides(target, left: .daw2, right: .daw3)                       // offset pair: not natural
        XCTAssertEqual(s.routeChoice(for: target), .custom(left: .daw2, right: .daw3))
    }

    // MARK: Writing

    func testChoosingAMixPairRoutesBothSides() {
        let s = makeState()
        let target = RouteTarget.output(label: label(s, 2))
        s.userSetRouteChoice(.mixPair(2), for: target)
        let sides = s.routeSides(target)
        XCTAssertEqual(sides.left, .m5)
        XCTAssertEqual(sides.right, .m6)
    }

    func testAMonoMixFeedsBothSides() {
        let s = makeState()
        let target = RouteTarget.output(label: label(s, 0))
        s.userSetRouteChoice(.monoMix(.m4), for: target)
        XCTAssertEqual(s.routeSides(target).left, .m4)
        XCTAssertEqual(s.routeSides(target).right, .m4)
    }

    func testChoosingOffClearsBothSides() {
        let s = makeState()
        let target = RouteTarget.output(label: label(s, 0))
        s.setRouteSides(target, left: .m1, right: .m2)
        s.userSetRouteChoice(.off, for: target)
        XCTAssertEqual(s.routeChoice(for: target), .off)
    }

    func testOutputPairsDoNotAffectEachOther() {
        let s = makeState()
        let a = RouteTarget.output(label: label(s, 0)), b = RouteTarget.output(label: label(s, 1))
        s.userSetRouteChoice(.mixPair(0), for: a)
        s.userSetRouteChoice(.sourcePair(.analog3), for: b)
        XCTAssertEqual(s.routeChoice(for: a), .mixPair(0))
        XCTAssertEqual(s.routeChoice(for: b), .sourcePair(.analog3))
    }

    func testCapturePairsWorkTheSameWay() {
        let s = makeState()
        let target = RouteTarget.capture(pair: 3)
        s.userSetRouteChoice(.mixPair(0), for: target)
        XCTAssertEqual(s.captureRoutes[6], .m1)
        XCTAssertEqual(s.captureRoutes[7], .m2)
        XCTAssertEqual(s.routeChoice(for: target), .mixPair(0))
    }

    func testCaptureChannelsStartAtFactoryAndResetToIt() {
        let s = makeState()
        for (channel, source) in s.profile.defaultCaptureSources.enumerated() { s.captureRoutes[channel] = source }
        XCTAssertTrue(s.isCaptureChannelAtFactory(3))
        XCTAssertFalse(s.captureDiffersFromFactory)

        s.userSetCaptureRoute(channel: 3, to: .m1)
        XCTAssertFalse(s.isCaptureChannelAtFactory(3))
        XCTAssertTrue(s.isCaptureChannelAtFactory(2))
        XCTAssertTrue(s.captureDiffersFromFactory)

        s.resetCaptureRoutesToFactory()
        XCTAssertTrue(s.isCaptureChannelAtFactory(3))
        XCTAssertFalse(s.captureDiffersFromFactory)
    }

    func testCaptureChannelsAreGroupedByKindOfInput() {
        let s = makeState()
        let groups = s.captureChannelGroups
        XCTAssertEqual(groups.map(\.title), ["Analog 1–8", "S/PDIF 1–2", "ADAT 1–8"])
        XCTAssertEqual(groups.flatMap(\.channels), Array(0..<18))
        XCTAssertEqual(s.factoryCaptureName(channel: 8), "S/PDIF 1")
    }

    func testAPairThatDoesNotExistIsIgnored() {
        let s = makeState()
        s.userSetRouteChoice(.mixPair(0), for: .capture(pair: 99))
        s.userSetRouteChoice(.mixPair(0), for: .output(label: "Nonexistent"))
        XCTAssertEqual(s.routeSides(.capture(pair: 99)).left, .off)
    }

    // MARK: Options

    func testOptionsOfferEachLinkedMixPairOnceAndASplitPairAsTwoMonoMixes() {
        let s = makeState()
        var options = s.routeChoiceOptions
        XCTAssertEqual(options.first, .off)
        for pair in 0..<4 { XCTAssertTrue(options.contains(.mixPair(pair))) }
        XCTAssertFalse(options.contains(.monoMix(.m3)))

        s.userSetMixPairLinked(1, linked: false)
        options = s.routeChoiceOptions
        XCTAssertFalse(options.contains(.mixPair(1)))
        XCTAssertTrue(options.contains(.monoMix(.m3)))
        XCTAssertTrue(options.contains(.monoMix(.m4)))
    }

    func testOptionsOfferTheNaturalPairsOfSourcesAndNoOthers() {
        let options = makeState().routeChoiceOptions
        XCTAssertTrue(options.contains(.sourcePair(.analog1)))
        XCTAssertTrue(options.contains(.sourcePair(.spdif1)))
        XCTAssertTrue(options.contains(.sourcePair(.adat7)))
        XCTAssertTrue(options.contains(.sourcePair(.daw19)))
        XCTAssertFalse(options.contains(.sourcePair(.analog2)))
        XCTAssertFalse(options.contains { if case .custom = $0 { return true } else { return false } })
        XCTAssertEqual(options.count, Set(options).count, "no duplicates")
    }

    // MARK: Names and colours

    func testAMixIsNamedAsTheUserNamedIt() {
        let s = makeState()
        XCTAssertEqual(s.routeChoiceName(.mixPair(0)), "Mix M1+M2")
        s.userSetMixAppearance(tab: 0, name: "Main Mix", colorHex: "")
        XCTAssertEqual(s.routeChoiceName(.mixPair(0)), "Main Mix")
        XCTAssertEqual(s.routeSourceName(.m2), "Main Mix")          // either half of a linked pair
    }

    func testASplitPairsMixesAreNamedOneByOne() {
        let s = makeState()
        s.userSetMixPairLinked(1, linked: false)
        XCTAssertEqual(s.routeChoiceName(.monoMix(.m3)), "Mix M3")
        s.userSetMixAppearance(tab: 3, name: "Click", colorHex: "")
        XCTAssertEqual(s.routeChoiceName(.monoMix(.m4)), "Click")
        XCTAssertEqual(s.routeChoiceName(.monoMix(.m3)), "Mix M3")
    }

    func testSourcePairsAndCustomChoicesAreNamedFromTheirSources() {
        let s = makeState()
        XCTAssertEqual(s.routeChoiceName(.sourcePair(.analog1)), "Analog 1+2")
        XCTAssertEqual(s.routeChoiceName(.sourcePair(.adat5)), "ADAT 5+6")
        XCTAssertEqual(s.routeChoiceName(.custom(left: .daw2, right: .analog1)), "DAW 2 / Analog 1")
        XCTAssertEqual(s.routeChoiceName(.off), "Off")
    }

    func testAMixRoutesWithItsOwnColourOrTheDefaultAccent() {
        let s = makeState()
        XCTAssertNil(s.routeColor(.off))
        XCTAssertEqual(s.routeColor(.m1)?.hexString, Theme.tabOutline.hexString)
        s.userSetMixAppearance(tab: 0, name: "", colorHex: "#F2C94C")
        XCTAssertEqual(s.routeColor(.m1)?.hexString, "#F2C94C")
        XCTAssertEqual(s.routeColor(.m2)?.hexString, "#F2C94C", "the other half of a linked pair")
        XCTAssertEqual(s.routeColor(.m3)?.hexString, Theme.tabOutline.hexString)
    }

    func testASourceRoutesWithItsInputTypeColour() {
        let s = makeState()
        XCTAssertEqual(s.routeColor(.analog1)?.hexString, SignalSource.analog1.accentColor.hexString)
        XCTAssertEqual(s.routeColor(.daw1)?.hexString, SignalSource.daw1.accentColor.hexString)
    }

    // MARK: Linking

    func testPairsStartLinkedAndCanBeSplit() {
        let s = makeState()
        let target = RouteTarget.output(label: label(s, 0))
        XCTAssertTrue(s.isRoutePairLinked(target))
        s.userSetRoutePairLinked(target, linked: false)
        XCTAssertFalse(s.isRoutePairLinked(target))
        XCTAssertTrue(s.isRoutePairLinked(.output(label: label(s, 1))), "only that pair")
    }

    func testSplittingChangesNoRoute() {
        let s = makeState()
        let target = RouteTarget.output(label: label(s, 0))
        s.setRouteSides(target, left: .m1, right: .m2)
        s.userSetRoutePairLinked(target, linked: false)
        XCTAssertEqual(s.routeSides(target).left, .m1)
        XCTAssertEqual(s.routeSides(target).right, .m2)
    }

    func testJoiningFollowsTheLeftSide() {
        let s = makeState()
        let target = RouteTarget.output(label: label(s, 0))
        s.userSetRoutePairLinked(target, linked: false)

        s.setRouteSides(target, left: .analog3, right: .daw1)
        s.userSetRoutePairLinked(target, linked: true)
        XCTAssertEqual(s.routeChoice(for: target), .sourcePair(.analog3))
        XCTAssertEqual(s.routeSides(target).right, .analog4)

        s.userSetRoutePairLinked(target, linked: false)
        s.setRouteSides(target, left: .m3, right: .daw1)
        s.userSetRoutePairLinked(target, linked: true)
        XCTAssertEqual(s.routeChoice(for: target), .mixPair(1))
        XCTAssertEqual(s.routeSides(target).right, .m4)
    }

    func testJoiningLeavesASideWithNoNaturalPartnerAlone() {
        let s = makeState()
        let target = RouteTarget.output(label: label(s, 0))
        s.userSetRoutePairLinked(target, linked: false)
        s.setRouteSides(target, left: .daw2, right: .analog1)               // DAW 2 has no partner on its right
        s.userSetRoutePairLinked(target, linked: true)
        XCTAssertEqual(s.routeSides(target).left, .daw2)
        XCTAssertEqual(s.routeSides(target).right, .analog1)
    }

    func testJoiningAnEmptyLeftSideClearsBoth() {
        let s = makeState()
        let target = RouteTarget.output(label: label(s, 0))
        s.userSetRoutePairLinked(target, linked: false)
        s.setRouteSides(target, left: .off, right: .m2)
        s.userSetRoutePairLinked(target, linked: true)
        XCTAssertEqual(s.routeChoice(for: target), .off)
    }

    func testJoiningOnASplitMixesLeftSideFeedsBothSides() {
        let s = makeState()
        s.userSetMixPairLinked(1, linked: false)
        let target = RouteTarget.output(label: label(s, 0))
        s.userSetRoutePairLinked(target, linked: false)
        s.setRouteSides(target, left: .m4, right: .daw1)
        s.userSetRoutePairLinked(target, linked: true)
        XCTAssertEqual(s.routeChoice(for: target), .monoMix(.m4))
    }

    // MARK: Side pickers

    func testAHalfOfALinkedMixPairIsNamedWithItsSide() {
        let s = makeState()
        s.userSetMixAppearance(tab: 0, name: "Main Mix", colorHex: "")
        XCTAssertEqual(s.routeSideName(.m1), "Main Mix L")
        XCTAssertEqual(s.routeSideName(.m2), "Main Mix R")
        XCTAssertEqual(s.routeSideName(.m3), "Mix M3+M4 L")
        XCTAssertEqual(s.routeSideName(.analog5), "Analog 5")
    }

    func testASplitMixIsNamedOnItsOwnWithoutASide() {
        let s = makeState()
        s.userSetMixPairLinked(1, linked: false)
        XCTAssertEqual(s.routeSideName(.m3), "Mix M3")
        s.userSetMixAppearance(tab: 3, name: "Click", colorHex: "")
        XCTAssertEqual(s.routeSideName(.m4), "Click")
    }

    func testACustomChoiceNamesItsSidesSoReversedMixesAreClear() {
        let s = makeState()
        XCTAssertEqual(s.routeChoiceName(.custom(left: .m2, right: .m1)), "Mix M1+M2 R / Mix M1+M2 L")
    }

    func testTheSidePickerGroupsMixesInputsAndDAWOutputs() {
        let groups = makeState().routeSideGroups
        XCTAssertEqual(groups.map(\.title), ["Mixes", "Inputs", "DAW"])
        XCTAssertEqual(groups[0].buses.count, 8)
        XCTAssertEqual(groups[1].buses.count, 18)               // 8 analogue, 2 S/PDIF, 8 ADAT
        XCTAssertEqual(groups[2].buses.count, 20)
        XCTAssertFalse(groups.flatMap(\.buses).contains(.off))
    }

    func testEveryOutputPairOfThe18i20HasBothSides() {
        let s = makeState()
        XCTAssertEqual(s.physicalOutputGroups.count, 10)
        for group in s.physicalOutputGroups {
            XCTAssertTrue(group.outputs.contains { $0.isLeft } && group.outputs.contains { !$0.isLeft }, group.label)
        }
    }
}
