import XCTest
@testable import ScarlettCore

final class MixGainTests: XCTestCase {
    func testCenterPanSendsFullLevelToBothSides() {
        XCTAssertEqual(MixGain.cellGain(level: -6, pan: 0, isLeft: true), -6, accuracy: 1e-9)
        XCTAssertEqual(MixGain.cellGain(level: -6, pan: 0, isLeft: false), -6, accuracy: 1e-9)
    }

    func testHardPanSilencesTheFarSide() {
        XCTAssertEqual(MixGain.cellGain(level: 0, pan: -1, isLeft: false), MixGain.floorDb)
        XCTAssertEqual(MixGain.cellGain(level: 0, pan: 1, isLeft: true), MixGain.floorDb)
        XCTAssertEqual(MixGain.cellGain(level: 0, pan: -1, isLeft: true), 0, accuracy: 1e-9)
    }

    func testDeriveLevelAndPanInvertsCellGain() {
        for (level, pan) in [(0.0, 0.0), (-12.0, -0.5), (-3.0, 0.25), (6.0, 0.9), (-20.0, -1.0)] {
            let left = MixGain.cellGain(level: level, pan: pan, isLeft: true)
            let right = MixGain.cellGain(level: level, pan: pan, isLeft: false)
            let back = MixGain.deriveLevelAndPan(left: left, right: right)
            // Hard pan floors at -128 dB rather than -∞, so it only inverts to within 1e-4.
            XCTAssertEqual(back.level, level, accuracy: 1e-6)
            XCTAssertEqual(back.pan, pan, accuracy: 1e-4)
        }
    }

    func testUnlinkedLevelsKeepTheGainsThePairWasSending() {
        for (level, pan) in [(0.0, 0.0), (-12.0, -0.5), (-3.0, 0.25), (6.0, 1.0), (-20.0, -1.0)] {
            let split = MixGain.unlinkedLevels(level: level, pan: pan)
            XCTAssertEqual(split.left, MixGain.cellGain(level: level, pan: pan, isLeft: true), accuracy: 1e-9)
            XCTAssertEqual(split.right, MixGain.cellGain(level: level, pan: pan, isLeft: false), accuracy: 1e-9)
        }
    }

    func testUnlinkedLevelsNeverGoBelowTheFloor() {
        // -100 dB panned almost hard would compute to about -140 dB.
        let split = MixGain.unlinkedLevels(level: -100, pan: 0.99)
        XCTAssertGreaterThanOrEqual(split.left, MixGain.floorDb)
        XCTAssertGreaterThanOrEqual(split.right, MixGain.floorDb)
    }

    func testStereoPositionsAtDefaultsAreHardLeftAndRight() {
        let p = MixGain.stereoPositions(pan: 0, width: 1)
        XCTAssertEqual(p.left, -1)
        XCTAssertEqual(p.right, 1)
    }

    func testPanningFoldsTheImageOntoTheChosenSide() {
        let half = MixGain.stereoPositions(pan: 0.5, width: 1)
        XCTAssertEqual(half.left, 0, accuracy: 1e-9)
        XCTAssertEqual(half.right, 1, accuracy: 1e-9)
        let full = MixGain.stereoPositions(pan: -1, width: 1)
        XCTAssertEqual(full.left, -1)
        XCTAssertEqual(full.right, -1)
    }

    func testZeroWidthPutsBothChannelsAtThePan() {
        let p = MixGain.stereoPositions(pan: 0.3, width: 0)
        XCTAssertEqual(p.left, 0.3, accuracy: 1e-9)
        XCTAssertEqual(p.right, 0.3, accuracy: 1e-9)
    }

    func testStereoPanWidthInvertsStereoPositions() {
        for (pan, width) in [(0.0, 1.0), (0.5, 1.0), (-0.5, 0.5), (0.4, 0.5), (0.0, 0.0), (-0.75, 0.3)] {
            let p = MixGain.stereoPositions(pan: pan, width: width)
            let back = MixGain.stereoPanWidth(left: p.left, right: p.right)
            XCTAssertEqual(back.pan, pan, accuracy: 1e-9)
            XCTAssertEqual(back.width, width, accuracy: 1e-9)
        }
    }

    func testWidthReadsAsFullWhenBothChannelsShareTheEdge() {
        let back = MixGain.stereoPanWidth(left: 1, right: 1)
        XCTAssertEqual(back.pan, 1)
        XCTAssertEqual(back.width, 1)
    }
}
