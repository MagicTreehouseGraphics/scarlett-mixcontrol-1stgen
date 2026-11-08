import XCTest
@testable import ScarlettCore

final class StereoSourceTests: XCTestCase {
    func testOddSourcesPairWithTheNextOne() {
        XCTAssertEqual(SignalSource.daw1.stereoRightPartner, .daw2)
        XCTAssertEqual(SignalSource.daw19.stereoRightPartner, .daw20)
        XCTAssertEqual(SignalSource.analog3.stereoRightPartner, .analog4)
        XCTAssertEqual(SignalSource.spdif1.stereoRightPartner, .spdif2)
        XCTAssertEqual(SignalSource.adat7.stereoRightPartner, .adat8)
    }

    func testEvenSourcesAndOffAreNeverTheLeftOfAPair() {
        XCTAssertNil(SignalSource.daw2.stereoRightPartner)
        XCTAssertNil(SignalSource.analog4.stereoRightPartner)
        XCTAssertNil(SignalSource.spdif2.stereoRightPartner)
        XCTAssertNil(SignalSource.off.stereoRightPartner)
    }

    func testEveryPartnerIsInTheSameFamilyAndFollowsOnDirectly() {
        for source in SignalSource.allCases {
            guard let right = source.stereoRightPartner else { continue }
            XCTAssertEqual(right.displayName.split(separator: " ").first,
                           source.displayName.split(separator: " ").first, "\(source)")
            XCTAssertEqual(Int(right.displayName.split(separator: " ").last!)!,
                           Int(source.displayName.split(separator: " ").last!)! + 1, "\(source)")
        }
    }

    func testPairsKeepTheOrderOfTheAvailableSources() {
        let available: [SignalSource] = [.off, .analog1, .analog2, .analog3, .analog4,
                                         .spdif1, .spdif2, .daw1, .daw2, .daw3, .daw4]
        XCTAssertEqual(SignalSource.stereoPairs(in: available).map(\.name),
                       ["Analog 1+2", "Analog 3+4", "S/PDIF 1+2", "DAW 1+2", "DAW 3+4"])
    }

    func testAPairNeedsBothSourcesToBeAvailable() {
        XCTAssertEqual(SignalSource.stereoPairs(in: [.analog1, .analog3, .analog4]).map(\.name),
                       ["Analog 3+4"])
    }

    func testPairNameUsesTheRightSourcesNumber() {
        XCTAssertEqual(StereoSourcePair(left: .adat5, right: .adat6).name, "ADAT 5+6")
    }
}
