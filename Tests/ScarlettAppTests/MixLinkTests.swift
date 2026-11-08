import XCTest
import ScarlettCore
@testable import ScarlettApp

/// Runs against a `MixerState` with no device, so nothing is sent over USB.
/// Without a device the profile falls back to the 8i6: 6 buses, 3 pairs.
@MainActor
final class MixLinkTests: XCTestCase {
    private func makeState() -> MixerState { MixerState(autoConnect: false) }

    private func gains(_ s: MixerState, channel: Int, pair: Int) -> (Double, Double) {
        (s.effectiveGain(channel: channel, busIdx: pair * 2),
         s.effectiveGain(channel: channel, busIdx: pair * 2 + 1))
    }

    func testPairsAreLinkedByDefault() {
        let s = makeState()
        XCTAssertTrue((0..<s.stereoPairCount).allSatisfy { s.isMixPairLinked($0) })
        s.userSetMixerLevel(channel: 0, busIdx: 1, level: -9)
        XCTAssertEqual(s.mixLevel(channel: 0, busIdx: 0), -9)
        XCTAssertEqual(s.mixLevel(channel: 0, busIdx: 1), -9)
    }

    func testUnlinkingChangesNoGain() {
        let s = makeState()
        s.userSetMixerLevel(channel: 0, busIdx: 0, level: -6)
        s.userSetMixerPan(channel: 0, pair: 0, pan: -0.5)
        s.userSetMixerLevel(channel: 1, busIdx: 0, level: 3)
        s.userSetMixerPan(channel: 1, pair: 0, pan: 1)
        let before = [gains(s, channel: 0, pair: 0), gains(s, channel: 1, pair: 0)]

        s.userSetMixPairLinked(0, linked: false)

        XCTAssertFalse(s.isMixPairLinked(0))
        XCTAssertEqual(gains(s, channel: 0, pair: 0).0, before[0].0, accuracy: 1e-9)
        XCTAssertEqual(gains(s, channel: 0, pair: 0).1, before[0].1, accuracy: 1e-9)
        XCTAssertEqual(gains(s, channel: 1, pair: 0).0, before[1].0, accuracy: 1e-9)
        XCTAssertEqual(gains(s, channel: 1, pair: 0).1, before[1].1, accuracy: 1e-9)
        XCTAssertEqual(s.mixerPans[0][0], 0)
    }

    func testUnlinkOnlyAffectsThatPair() {
        let s = makeState()
        s.userSetMixerLevel(channel: 0, busIdx: 2, level: -4)
        s.userSetMixPairLinked(0, linked: false)
        XCTAssertTrue(s.isMixPairLinked(1))
        XCTAssertEqual(s.mixLevel(channel: 0, busIdx: 2), -4)
        XCTAssertEqual(s.mixLevel(channel: 0, busIdx: 3), -4)
    }

    func testUnlinkedBusesMoveIndependently() {
        let s = makeState()
        s.userSetMixPairLinked(0, linked: false)
        s.userSetMixerLevel(channel: 0, busIdx: 0, level: -10)
        s.userSetMixerLevel(channel: 0, busIdx: 1, level: -2)
        XCTAssertEqual(s.mixLevel(channel: 0, busIdx: 0), -10)
        XCTAssertEqual(s.mixLevel(channel: 0, busIdx: 1), -2)
        XCTAssertEqual(gains(s, channel: 0, pair: 0).0, -10)
        XCTAssertEqual(gains(s, channel: 0, pair: 0).1, -2)

        s.userSetMixerLevel(channel: 0, busIdx: 0, level: -20)
        XCTAssertEqual(s.mixLevel(channel: 0, busIdx: 1), -2)
    }

    func testPanIsIgnoredWhileUnlinked() {
        let s = makeState()
        s.userSetMixPairLinked(0, linked: false)
        s.userSetMixerLevel(channel: 0, busIdx: 0, level: -10)
        s.userSetMixerLevel(channel: 0, busIdx: 1, level: -2)
        s.userSetMixerPan(channel: 0, pair: 0, pan: 1)
        XCTAssertEqual(s.mixerPans[0][0], 0)
        XCTAssertEqual(gains(s, channel: 0, pair: 0).0, -10)
        XCTAssertEqual(gains(s, channel: 0, pair: 0).1, -2)
    }

    func testRelinkingKeepsTheLeftBusAndOverwritesTheRight() {
        let s = makeState()
        s.userSetMixPairLinked(0, linked: false)
        s.userSetMixerLevel(channel: 0, busIdx: 0, level: -10)
        s.userSetMixerLevel(channel: 0, busIdx: 1, level: -2)

        s.userSetMixPairLinked(0, linked: true)

        XCTAssertTrue(s.isMixPairLinked(0))
        XCTAssertEqual(s.mixLevel(channel: 0, busIdx: 0), -10)
        XCTAssertEqual(s.mixLevel(channel: 0, busIdx: 1), -10)
        XCTAssertEqual(s.mixerPans[0][0], 0)
        XCTAssertEqual(gains(s, channel: 0, pair: 0).0, -10)
        XCTAssertEqual(gains(s, channel: 0, pair: 0).1, -10)
        XCTAssertEqual(s.mixerRightLevels[0][0], 0)
    }

    func testRelinkingOnlyNeedsConfirmingWhenTheMixesDiffer() {
        let s = makeState()
        XCTAssertFalse(s.relinkingOverwrites(pair: 0))          // already linked
        s.userSetMixPairLinked(0, linked: false)
        XCTAssertFalse(s.relinkingOverwrites(pair: 0))          // identical so far
        s.userSetMixerLevel(channel: 2, busIdx: 1, level: -5)
        XCTAssertTrue(s.relinkingOverwrites(pair: 0))
        s.userSetMixerLevel(channel: 2, busIdx: 0, level: -5)
        XCTAssertFalse(s.relinkingOverwrites(pair: 0))
    }

    func testUnlinkingGivesStereoLinkedChannelsOneSharedLevelOnBothMixes() {
        let s = makeState()
        s.userToggleLink(channel: 4)
        s.userSetMixerLevel(channel: 4, busIdx: 0, level: -6)
        XCTAssertEqual(gains(s, channel: 4, pair: 0).1, MixGain.floorDb)   // hard left

        s.userSetMixPairLinked(0, linked: false)

        for ch in [4, 5] {
            XCTAssertEqual(s.mixLevel(channel: ch, busIdx: 0), -6)
            XCTAssertEqual(s.mixLevel(channel: ch, busIdx: 1), -6)
            XCTAssertEqual(gains(s, channel: ch, pair: 0).0, -6)
            XCTAssertEqual(gains(s, channel: ch, pair: 0).1, -6)
        }
    }

    func testUnlinkingAndRelinkingStereoLinkedChannelsChangesNothing() {
        let s = makeState()
        s.userToggleLink(channel: 4)
        s.userSetMixerLevel(channel: 4, busIdx: 0, level: -6)
        let before = [gains(s, channel: 4, pair: 0), gains(s, channel: 5, pair: 0)]

        s.userSetMixPairLinked(0, linked: false)
        XCTAssertFalse(s.relinkingOverwrites(pair: 0))
        s.userSetMixPairLinked(0, linked: true)

        XCTAssertEqual(s.mixerLevels[4][0], -6)
        XCTAssertEqual(s.mixerLevels[5][0], -6)
        XCTAssertEqual(gains(s, channel: 4, pair: 0).0, before[0].0, accuracy: 1e-9)
        XCTAssertEqual(gains(s, channel: 4, pair: 0).1, before[0].1, accuracy: 1e-9)
        XCTAssertEqual(gains(s, channel: 5, pair: 0).0, before[1].0, accuracy: 1e-9)
        XCTAssertEqual(gains(s, channel: 5, pair: 0).1, before[1].1, accuracy: 1e-9)
    }

    func testRelinkingStereoLinkedChannelsUsesTheLeftMixLevelForBoth() {
        let s = makeState()
        s.userToggleLink(channel: 4)
        s.userSetMixPairLinked(0, linked: false)
        s.userSetMixerLevel(channel: 4, busIdx: 0, level: -9)   // moves channel 5 too
        s.userSetMixerLevel(channel: 4, busIdx: 1, level: -2)
        s.userSetMixPairLinked(0, linked: true)
        XCTAssertEqual(s.mixerLevels[4][0], -9)
        XCTAssertEqual(s.mixerLevels[5][0], -9)
    }

    func testRelinkingRestoresHardPanForStereoLinkedChannels() {
        let s = makeState()
        s.userToggleLink(channel: 4)          // channels 4 + 5 become a stereo pair
        XCTAssertEqual(s.mixerPans[4][0], -1)
        s.userSetMixPairLinked(0, linked: false)
        s.userSetMixPairLinked(0, linked: true)
        XCTAssertEqual(s.mixerPans[4][0], -1)
        XCTAssertEqual(s.mixerPans[5][0], 1)
        XCTAssertEqual(s.mixerPans[0][0], 0)
    }

    func testStereoLinkedChannelsShareAnUnlinkedBusLevel() {
        let s = makeState()
        s.userToggleLink(channel: 4)
        s.userSetMixPairLinked(1, linked: false)
        s.userSetMixerLevel(channel: 4, busIdx: 3, level: -7)
        XCTAssertEqual(s.mixLevel(channel: 5, busIdx: 3), -7)
        XCTAssertEqual(s.mixLevel(channel: 5, busIdx: 2), s.mixerLevels[5][1])
    }

    func testChannelLinkLeavesUnlinkedPairsAlone() {
        let s = makeState()
        s.userSetMixPairLinked(1, linked: false)
        s.userToggleLink(channel: 2)
        XCTAssertEqual(s.mixerPans[2][1], 0)
        XCTAssertEqual(s.mixerPans[2][0], -1)
    }

    func testCopyingAPairCopiesItsLinkState() {
        let s = makeState()
        s.userSetMixPairLinked(0, linked: false)
        s.userSetMixerLevel(channel: 0, busIdx: 0, level: -8)
        s.userSetMixerLevel(channel: 0, busIdx: 1, level: -3)
        s.userCopyMixPair(from: 0, to: 2)
        XCTAssertFalse(s.isMixPairLinked(2))
        XCTAssertEqual(s.mixLevel(channel: 0, busIdx: 4), -8)
        XCTAssertEqual(s.mixLevel(channel: 0, busIdx: 5), -3)

        s.userCopyMixPair(from: 1, to: 2)     // pair 1 is still linked
        XCTAssertTrue(s.isMixPairLinked(2))
    }

    func testSnapshotsRoundTripTheLinkState() throws {
        let s = makeState()
        s.userSetMixPairLinked(1, linked: false)
        s.userSetMixerLevel(channel: 3, busIdx: 3, level: -5)

        let data = try JSONEncoder().encode(s.currentSnapshot(named: "x"))
        let decoded = try JSONDecoder().decode(ScarlettPreset.self, from: data)

        XCTAssertEqual(decoded.unlinkedMixes, [1])
        XCTAssertEqual(decoded.mixerRightLevels?[3][1], -5)
    }

    func testAllLinkedSnapshotsOmitTheLinkFields() throws {
        let snapshot = makeState().currentSnapshot(named: "x")
        XCTAssertNil(snapshot.unlinkedMixes)
        XCTAssertNil(snapshot.mixerRightLevels)
    }

    func testPresetsSavedBeforeUnlinkingStillDecodeAsLinked() throws {
        let s = makeState()
        let data = try JSONEncoder().encode(s.currentSnapshot(named: "old"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "unlinkedMixes")
        json.removeValue(forKey: "mixerRightLevels")
        let old = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(ScarlettPreset.self, from: old)

        XCTAssertNil(decoded.unlinkedMixes)
        XCTAssertNil(decoded.mixerRightLevels)
    }

    // MARK: - Stereo source pairs

    func testLinkingFeedsAnEmptyRightChannelFromTheLeftsPartner() {
        let s = makeState()
        s.userSetMixerSource(channel: 4, source: .analog1)
        s.userToggleLink(channel: 4)
        XCTAssertEqual(s.mixerSources[5], .analog2)
    }

    func testLinkingKeepsARightChannelThatAlreadyHasASource() {
        let s = makeState()
        s.userSetMixerSource(channel: 4, source: .analog1)
        s.userSetMixerSource(channel: 5, source: .spdif1)
        s.userToggleLink(channel: 4)
        XCTAssertEqual(s.mixerSources[5], .spdif1)
        XCTAssertEqual(s.stereoSourceChoice(leftChannel: 4), .custom(.analog1, .spdif1))
    }

    func testLinkingDoesNotTakeThePartnerFromAnotherChannel() {
        let s = makeState()
        s.userSetMixerSource(channel: 8, source: .analog2)
        s.userSetMixerSource(channel: 4, source: .analog1)
        s.userToggleLink(channel: 4)
        XCTAssertEqual(s.mixerSources[5], .off)
        XCTAssertEqual(s.mixerSources[8], .analog2)
    }

    func testPickingAStereoSourceFeedsBothChannels() {
        let s = makeState()
        s.userToggleLink(channel: 4)
        s.userSetStereoSource(leftChannel: 4, to: .pair(StereoSourcePair(left: .analog3, right: .analog4)))
        XCTAssertEqual(s.mixerSources[4], .analog3)
        XCTAssertEqual(s.mixerSources[5], .analog4)
        XCTAssertEqual(s.stereoSourceChoice(leftChannel: 4).name, "Analog 3+4")

        s.userSetStereoSource(leftChannel: 4, to: .off)
        XCTAssertEqual(s.mixerSources[4], .off)
        XCTAssertEqual(s.mixerSources[5], .off)
        XCTAssertEqual(s.stereoSourceChoice(leftChannel: 4), .off)
    }

    func testPickingAStereoSourceTakesItFromAnyOtherChannel() {
        let s = makeState()
        s.userSetMixerSource(channel: 9, source: .analog4)
        s.userToggleLink(channel: 4)
        s.userSetStereoSource(leftChannel: 4, to: .pair(StereoSourcePair(left: .analog3, right: .analog4)))
        XCTAssertEqual(s.mixerSources[9], .off)
        XCTAssertEqual(s.mixerSources[5], .analog4)
    }

    func testStereoSourceOptionsAreOffPlusWholePairs() {
        let options = makeState().stereoSourceOptions
        XCTAssertEqual(options.first, .off)
        XCTAssertTrue(options.dropFirst().allSatisfy {
            if case .pair(let p) = $0 { return p.left.stereoRightPartner == p.right }
            return false
        })
        XCTAssertTrue(options.contains(.pair(StereoSourcePair(left: .analog1, right: .analog2))))
    }

    // MARK: - Stereo pan and width

    func testStereoPairStartsHardLeftAndRightWithOneFader() {
        let s = makeState()
        s.userToggleLink(channel: 4)
        let image = s.stereoPanWidth(leftChannel: 4, pair: 0)
        XCTAssertEqual(image.pan, 0, accuracy: 1e-9)
        XCTAssertEqual(image.width, 1, accuracy: 1e-9)

        s.userSetMixerLevel(channel: 4, busIdx: 0, level: -6)
        XCTAssertEqual(s.mixerLevels[4][0], -6)
        XCTAssertEqual(s.mixerLevels[5][0], -6)
        XCTAssertEqual(gains(s, channel: 4, pair: 0).0, -6)
        XCTAssertEqual(gains(s, channel: 4, pair: 0).1, MixGain.floorDb)
        XCTAssertEqual(gains(s, channel: 5, pair: 0).1, -6)
    }

    func testPanningRightMovesTheLeftChannelOverAndAddsItToTheRightSide() {
        let s = makeState()
        s.userToggleLink(channel: 4)
        s.userSetMixerLevel(channel: 4, busIdx: 0, level: -6)

        s.userSetStereoPan(leftChannel: 4, pair: 0, pan: 0.5)
        // Left channel now at center: on both sides.  Right channel stays hard right.
        XCTAssertEqual(gains(s, channel: 4, pair: 0).0, -6, accuracy: 1e-6)
        XCTAssertEqual(gains(s, channel: 4, pair: 0).1, -6, accuracy: 1e-6)
        XCTAssertEqual(gains(s, channel: 5, pair: 0).0, MixGain.floorDb)
        XCTAssertEqual(gains(s, channel: 5, pair: 0).1, -6, accuracy: 1e-6)

        s.userSetStereoPan(leftChannel: 4, pair: 0, pan: 1)
        // Both channels on the right output only.
        XCTAssertEqual(gains(s, channel: 4, pair: 0).0, MixGain.floorDb)
        XCTAssertEqual(gains(s, channel: 4, pair: 0).1, -6, accuracy: 1e-6)
        XCTAssertEqual(gains(s, channel: 5, pair: 0).0, MixGain.floorDb)
        XCTAssertEqual(gains(s, channel: 5, pair: 0).1, -6, accuracy: 1e-6)
    }

    func testPanningLeftMirrorsPanningRight() {
        let s = makeState()
        s.userToggleLink(channel: 4)
        s.userSetStereoPan(leftChannel: 4, pair: 0, pan: -1)
        XCTAssertEqual(gains(s, channel: 4, pair: 0).0, 0)
        XCTAssertEqual(gains(s, channel: 4, pair: 0).1, MixGain.floorDb)
        XCTAssertEqual(gains(s, channel: 5, pair: 0).0, 0)
        XCTAssertEqual(gains(s, channel: 5, pair: 0).1, MixGain.floorDb)
    }

    func testWidthNarrowsTheImageTowardMono() {
        let s = makeState()
        s.userToggleLink(channel: 4)
        s.userSetStereoWidth(leftChannel: 4, pair: 0, width: 0)
        for ch in [4, 5] {
            XCTAssertEqual(gains(s, channel: ch, pair: 0).0, 0)
            XCTAssertEqual(gains(s, channel: ch, pair: 0).1, 0)
        }
    }

    func testPanAndWidthKeepEachOtherAndTheFader() {
        let s = makeState()
        s.userToggleLink(channel: 4)
        s.userSetStereoWidth(leftChannel: 4, pair: 0, width: 0.5)
        s.userSetStereoPan(leftChannel: 4, pair: 0, pan: 0.4)
        var image = s.stereoPanWidth(leftChannel: 4, pair: 0)
        XCTAssertEqual(image.pan, 0.4, accuracy: 1e-9)
        XCTAssertEqual(image.width, 0.5, accuracy: 1e-9)

        s.userSetMixerLevel(channel: 4, busIdx: 0, level: -10)
        image = s.stereoPanWidth(leftChannel: 4, pair: 0)
        XCTAssertEqual(image.pan, 0.4, accuracy: 1e-9)
        XCTAssertEqual(image.width, 0.5, accuracy: 1e-9)

        s.userSetStereoWidth(leftChannel: 4, pair: 0, width: 0.8)
        XCTAssertEqual(s.stereoPanWidth(leftChannel: 4, pair: 0).pan, 0.4, accuracy: 1e-9)
    }

    func testWidthMeansNothingAtFullPan() {
        let s = makeState()
        s.userToggleLink(channel: 4)
        s.userSetStereoPan(leftChannel: 4, pair: 0, pan: 1)
        s.userSetStereoWidth(leftChannel: 4, pair: 0, width: 0.2)
        XCTAssertEqual(s.mixerPans[4][0], 1)
        XCTAssertEqual(s.mixerPans[5][0], 1)
    }

    func testPanAndWidthSnapAtTheirDefaults() {
        let s = makeState()
        s.userToggleLink(channel: 4)
        s.userSetStereoPan(leftChannel: 4, pair: 0, pan: 0.03)
        XCTAssertEqual(s.stereoPanWidth(leftChannel: 4, pair: 0).pan, 0)
        s.userSetStereoWidth(leftChannel: 4, pair: 0, width: 0.97)
        XCTAssertEqual(s.stereoPanWidth(leftChannel: 4, pair: 0).width, 1)
    }

    func testPanIsPerMixPair() {
        let s = makeState()
        s.userToggleLink(channel: 4)
        s.userSetStereoPan(leftChannel: 4, pair: 0, pan: 1)
        XCTAssertEqual(s.stereoPanWidth(leftChannel: 4, pair: 1).pan, 0)
    }

    func testStereoPanDoesNothingWithoutAStereoLinkOrOnMonoMixes() {
        let s = makeState()
        s.userSetStereoPan(leftChannel: 4, pair: 0, pan: 1)                  // channels not linked
        XCTAssertEqual(s.mixerPans[4][0], 0)

        s.userToggleLink(channel: 4)
        s.userSetMixPairLinked(0, linked: false)
        s.userSetStereoPan(leftChannel: 4, pair: 0, pan: 1)                  // mono mixes
        s.userSetStereoWidth(leftChannel: 4, pair: 0, width: 0)
        XCTAssertEqual(s.mixerPans[4][0], 0)
        XCTAssertEqual(s.mixerPans[5][0], 0)
    }

    func testRelinkingMixesPutsAPannedPairBackHardLeftAndRight() {
        let s = makeState()
        s.userToggleLink(channel: 4)
        s.userSetStereoPan(leftChannel: 4, pair: 0, pan: 0.6)
        s.userSetMixPairLinked(0, linked: false)
        s.userSetMixPairLinked(0, linked: true)
        XCTAssertEqual(s.mixerPans[4][0], -1)
        XCTAssertEqual(s.mixerPans[5][0], 1)
    }
}
