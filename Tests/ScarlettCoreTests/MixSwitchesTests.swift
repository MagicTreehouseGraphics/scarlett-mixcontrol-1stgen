import XCTest
@testable import ScarlettCore

final class MixSwitchesTests: XCTestCase {
    func testChannelWideIsOnlyWhereTheSwitchIsOnInEveryMix() {
        XCTAssertEqual(MixSwitches.channelWide([[true, true], [true, false], [false, false]]),
                       [true, false, false])
    }

    func testPerBusIsOmittedWhenEveryChannelIsTheSameInAllMixes() {
        XCTAssertNil(MixSwitches.perBus([[true, true], [false, false]]))
        XCTAssertEqual(MixSwitches.perBus([[true, false], [false, false]]), [[true, false], [false, false]])
    }

    func testOldSavesSpreadAChannelsSwitchOverEveryMix() {
        let rows = MixSwitches.adopted(perBus: nil, perChannel: [true, false, true], rows: 3, buses: 4)
        XCTAssertEqual(rows, [[true, true, true, true], [false, false, false, false], [true, true, true, true]])
    }

    func testPerMixSwitchesWinWhenTheyFit() {
        let saved = [[true, false], [false, true]]
        XCTAssertEqual(MixSwitches.adopted(perBus: saved, perChannel: [false, false], rows: 2, buses: 2), saved)
    }

    func testPerMixSwitchesThatDontFitFallBackToThePerChannelOnes() {
        let rows = MixSwitches.adopted(perBus: [[true, false, true]], perChannel: [true, false], rows: 2, buses: 2)
        XCTAssertEqual(rows, [[true, true], [false, false]])
    }

    func testMissingOrWrongSizedPerChannelSwitchesMeanAllOff() {
        XCTAssertEqual(MixSwitches.adopted(perBus: nil, perChannel: [true], rows: 2, buses: 2),
                       [[false, false], [false, false]])
    }

    func testWhatOlderVersionsReadMatchesWhatTheyWouldHaveSaved() {
        // A channel muted in some mixes only reads as not muted to an older version.
        let rows = [[true, true, true], [true, false, false]]
        XCTAssertEqual(MixSwitches.channelWide(rows), [true, false])
        XCTAssertEqual(MixSwitches.adopted(perBus: MixSwitches.perBus(rows), perChannel: MixSwitches.channelWide(rows),
                                           rows: 2, buses: 3), rows)
    }
}
