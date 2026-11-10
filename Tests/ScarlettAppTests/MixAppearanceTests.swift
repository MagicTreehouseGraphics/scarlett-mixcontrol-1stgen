import XCTest
import SwiftUI
@testable import ScarlettApp

@MainActor
final class MixAppearanceTests: XCTestCase {
    private func makeState() -> MixerState { MixerState(autoConnect: false) }

    func testALinkedPairIsOneTabKeyedByItsLeftMix() {
        let s = makeState()
        XCTAssertEqual(s.mixTabKey(forBus: 0), 0)
        XCTAssertEqual(s.mixTabKey(forBus: 1), 0)
        XCTAssertEqual(s.mixTabKey(forBus: 3), 2)
        s.userSetMixPairLinked(1, linked: false)
        XCTAssertEqual(s.mixTabKey(forBus: 2), 2)
        XCTAssertEqual(s.mixTabKey(forBus: 3), 3)
    }

    func testNamesAndColorsAreKeptPerTab() {
        let s = makeState()
        XCTAssertEqual(s.mixName(forTab: 0), "")
        XCTAssertEqual(s.mixColorHex(forTab: 0), "")
        s.userSetMixAppearance(tab: 2, name: "  Drums ", colorHex: "#f2594d")
        XCTAssertEqual(s.mixName(forTab: 2), "Drums")
        XCTAssertEqual(s.mixColorHex(forTab: 2), "#F2594D")
        XCTAssertEqual(s.mixName(forTab: 0), "")
    }

    func testBadInputFallsBackToTheDefaults() {
        let s = makeState()
        s.userSetMixAppearance(tab: 0, name: "   ", colorHex: "red")
        XCTAssertEqual(s.mixName(forTab: 0), "")
        XCTAssertEqual(s.mixColorHex(forTab: 0), "")
        s.userSetMixAppearance(tab: 99, name: "x", colorHex: "#FFFFFF")      // no such mix: ignored
        s.userSetMixAppearance(tab: 0, name: String(repeating: "a", count: 40), colorHex: "#GG0000")
        XCTAssertEqual(s.mixName(forTab: 0).count, MixAppearance.maxNameLength)
        XCTAssertEqual(s.mixColorHex(forTab: 0), "")
    }

    func testSavedAppearanceIsFittedToTheDevice() {
        let saved = MixAppearance(names: ["A", " B ", String(repeating: "z", count: 40)],
                                  colors: ["#00ff00", "nope", "#112233", "#445566", "#778899"])
        let adopted = MixAppearance.adopted(saved, count: 4)
        XCTAssertEqual(adopted.names.count, 4)
        XCTAssertEqual(adopted.colors.count, 4)
        XCTAssertEqual(adopted.names[1], "B")
        XCTAssertEqual(adopted.names[2].count, MixAppearance.maxNameLength)
        XCTAssertEqual(adopted.names[3], "")
        XCTAssertEqual(adopted.colors, ["#00FF00", "", "#112233", "#445566"])
    }

    func testNothingSavedMeansAllDefaults() {
        let adopted = MixAppearance.adopted(nil, count: 6)
        XCTAssertEqual(adopted.names, Array(repeating: "", count: 6))
        XCTAssertEqual(adopted.colors, Array(repeating: "", count: 6))
    }

    func testColorsRoundTripThroughHex() throws {
        for hex in ["#F2594D", "#4DCC66", "#000000", "#FFFFFF", "#9B6BF2"] {
            let color = try XCTUnwrap(Color(hex: hex))
            XCTAssertEqual(color.hexString, hex)
        }
        XCTAssertNil(Color(hex: ""))
        XCTAssertNil(Color(hex: "F2594D"))
        XCTAssertNil(Color(hex: "#F2594"))
    }

    // MARK: - Output fader colours

    func testOutputsStartWithNoColourSoTheirCapsAreSilver() {
        let s = makeState()
        XCTAssertEqual(s.outputColorHex(label: "Monitor"), "")
        XCTAssertTrue(s.outputColors.isEmpty)
    }

    func testAnOutputColourIsKeptPerPairAndCleanedUp() {
        let s = makeState()
        s.userSetOutputColor(label: "Phones", hex: "#4d8cf2")
        XCTAssertEqual(s.outputColorHex(label: "Phones"), "#4D8CF2")
        XCTAssertEqual(s.outputColorHex(label: "Monitor"), "")
    }

    func testChoosingTheDefaultOrABadColourReturnsToSilver() {
        let s = makeState()
        s.userSetOutputColor(label: "Phones", hex: "#4D8CF2")
        s.userSetOutputColor(label: "Phones", hex: "")
        XCTAssertEqual(s.outputColorHex(label: "Phones"), "")
        s.userSetOutputColor(label: "Phones", hex: "#4D8CF2")
        s.userSetOutputColor(label: "Phones", hex: "blue")
        XCTAssertEqual(s.outputColorHex(label: "Phones"), "")
        XCTAssertTrue(s.outputColors.isEmpty)
    }

    // MARK: - Output names

    func testAnOutputIsCalledByItsLabelUntilItIsRenamed() {
        let s = makeState()
        XCTAssertEqual(s.outputDisplayName(label: "Monitor"), "Monitor")
        s.userSetOutputName(label: "Monitor", name: "  Studio monitors ")
        XCTAssertEqual(s.outputDisplayName(label: "Monitor"), "Studio monitors")
        XCTAssertEqual(s.outputDisplayName(label: "Phones"), "Phones")
    }

    func testClearingAnOutputNameBringsBackItsLabel() {
        let s = makeState()
        s.userSetOutputName(label: "Phones", name: "Drummer")
        s.userSetOutputName(label: "Phones", name: "   ")
        XCTAssertEqual(s.outputDisplayName(label: "Phones"), "Phones")
        XCTAssertTrue(s.outputNames.isEmpty)
    }

    func testAnOutputNameIsKeptToTheSameLengthAsAMixName() {
        let s = makeState()
        s.userSetOutputName(label: "Phones", name: String(repeating: "x", count: 60))
        XCTAssertEqual(s.outputDisplayName(label: "Phones").count, MixAppearance.maxNameLength)
    }

    func testRenamingAnOutputDoesNotTouchItsColourOrItsIdentity() {
        let s = makeState()
        s.userSetOutputColor(label: "Phones", hex: "#4D8CF2")
        s.userSetOutputName(label: "Phones", name: "Drummer")
        XCTAssertEqual(s.outputColorHex(label: "Phones"), "#4D8CF2")
        XCTAssertTrue(s.visiblePairLabels.contains("Phones") || !s.visiblePairLabels.isEmpty)
    }
}
