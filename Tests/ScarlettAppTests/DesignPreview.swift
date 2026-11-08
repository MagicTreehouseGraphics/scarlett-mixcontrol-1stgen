import XCTest
import SwiftUI
import AppKit
import ScarlettCore
@testable import ScarlettApp

/// Renders parts of the mixer to PNG with sample levels, to look at the design
/// without the app or a device.  Skipped unless RENDER_PREVIEWS names a folder:
///   RENDER_PREVIEWS=/tmp/previews swift test --filter DesignPreview
@MainActor
final class DesignPreview: XCTestCase {
    func testRenderPreviews() throws {
        guard let path = ProcessInfo.processInfo.environment["RENDER_PREVIEWS"] else {
            throw XCTSkip("Set RENDER_PREVIEWS to a folder to render the previews")
        }
        let dir = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let state = sampleState()
        let appearance = AppearanceSettings.shared
        let (savedLook, savedGlow) = (appearance.look, appearance.meterGlow)
        defer { (appearance.look, appearance.meterGlow) = (savedLook, savedGlow) }

        for (look, glow, name) in [(MixerLook.classic, MeterGlow.full, "classic"),
                                   (.analog, .full, "analog"), (.analog, .simple, "analog-simple")] {
            appearance.look = look
            appearance.meterGlow = glow
            try render(closeUps, to: dir.appendingPathComponent("closeup-\(name).png"), scale: 4)
            try render(levels, to: dir.appendingPathComponent("levels-\(name).png"), scale: 3)
            try render(strips(state), to: dir.appendingPathComponent("strips-\(name).png"), scale: 2)
            try timeMeter(name)
        }
        appearance.look = .analog
        appearance.meterGlow = .full
        try renderWindow(page(state, spare: 140), size: CGSize(width: 1500, height: 780),
                         to: dir.appendingPathComponent("page.png"))
        appearance.look = .classic
        try renderWindow(page(state, spare: 140), size: CGSize(width: 1500, height: 780),
                         to: dir.appendingPathComponent("page-classic.png"))
    }

    /// The mixer page as the window shows it: padded, on the window colour.
    private func page(_ state: MixerState, spare: CGFloat) -> some View {
        MatrixMixerView(state: state)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.background)
            .environment(\.faderHeight, 300)
            .environment(\.pageSpareHeight, spare)
    }

    /// Draws the view in a real (never shown) window, so scroll views, menus
    /// and pickers come out as in the app.  `ImageRenderer` can't draw those.
    private func renderWindow(_ view: some View, size: CGSize, to url: URL) throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI settle: measured sizes and onAppear work arrive on later passes.
        for _ in 0..<6 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            host.layoutSubtreeIfNeeded()
        }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    /// Meters at rising levels, to see the glow grow with the signal.
    private var levels: some View {
        HStack(spacing: 22) {
            ForEach([-48.0, -30, -18, -9, -3, 0], id: \.self) { db in
                VerticalMeter(db: db, peakDb: db + 1, maxPeakDb: db + 2)
            }
        }
        .padding(16)
        .background(Theme.panel)
        .environment(\.faderHeight, 260)
    }

    // MARK: - Content

    private var closeUps: some View {
        HStack(alignment: .top, spacing: 18) {
            meterColumn(fader: 0, level: -14, peak: -11, max: -9)
            meterColumn(fader: -12, level: -4, peak: -3, max: -2)
            meterColumn(fader: 4, level: 0, peak: 0, max: 0)
            HStack(spacing: 4) {
                VerticalFader(db: .constant(-8), axis: .attenuation, tint: Theme.meterHigh)
                VerticalMeter(db: -9, peakDb: -7, maxPeakDb: -5, axis: .attenuation)
                VerticalMeter(db: -12, peakDb: -10, maxPeakDb: -6, axis: .attenuation)
                DbScale(axis: .attenuation)
            }
            VStack(spacing: 10) {
                HStack(spacing: 4) {
                    StripButton(letter: "M", active: false, activeColor: Theme.muteActive) {}
                    StripButton(letter: "S", active: false, activeColor: Theme.soloActive) {}
                    LinkButton(active: false) {}
                }
                HStack(spacing: 4) {
                    StripButton(letter: "M", active: true, activeColor: Theme.muteActive) {}
                    StripButton(letter: "S", active: true, activeColor: Theme.soloActive) {}
                    LinkButton(active: true) {}
                }
            }
        }
        .padding(16)
        .background(Theme.panel)
        .environment(\.faderHeight, 260)
    }

    private func meterColumn(fader: Double, level: Double, peak: Double, max: Double) -> some View {
        HStack(spacing: 4) {
            VerticalFader(db: .constant(fader))
            VerticalMeter(db: level, peakDb: peak, maxPeakDb: max)
            DbScale()
        }
    }

    private func strips(_ state: MixerState) -> some View {
        HStack(alignment: .top, spacing: 6) {
            ChannelStrip(channel: 0, state: state)
            ChannelStrip(channel: 1, state: state)
            ChannelStrip(channel: 4, state: state)
            OutputsPanel(state: state)
        }
        .padding(16)
        .background(Theme.tabPanel)
        .environment(\.faderHeight, 300)
    }

    /// Rough cost of drawing one meter, as the live view does ~20 times a
    /// second for every meter on screen.  Thirty meters per render, so the
    /// renderer's own setup is spread thin.
    private func timeMeter(_ name: String) throws {
        let runs = 40, meters = 30
        let start = Date()
        for run in 0..<runs {
            let row = HStack(spacing: 4) {
                ForEach(0..<meters, id: \.self) { i in
                    VerticalMeter(db: -Double((i * 7 + run) % 50), peakDb: -5, maxPeakDb: -3)
                }
            }
            let renderer = ImageRenderer(content: row.environment(\.faderHeight, 300))
            renderer.scale = 2
            _ = renderer.cgImage
        }
        let ms = Date().timeIntervalSince(start) * 1000 / Double(runs * meters)
        print("DesignPreview: one \(name) meter takes \(String(format: "%.3f", ms)) ms to render")
    }

    // MARK: - Sample state

    private func sampleState() -> MixerState {
        let state = MixerState(autoConnect: false)
        let sources: [SignalSource] = [.analog1, .analog2, .analog3, .analog4, .daw3, .daw4,
                                       .spdif1, .spdif2, .daw5, .daw6]
        for (ch, source) in sources.enumerated() {
            state.userSetMixerSource(channel: ch, source: source)
        }
        state.userToggleLink(channel: 4)
        for (ch, level) in [(0, 0.0), (1, -6), (2, 0), (3, -18), (4, -10), (6, 0), (8, 2)] {
            state.userSetMixerLevel(channel: ch, busIdx: 0, level: level)
        }
        state.peaks = PeakReading(
            inputs: [-12, -20, -4, -30, -60, -60, -60, -60, -60, -60, -60, -60, -60, -60, -60, -60, -60, -60],
            daw: [-8, -9, -6, -3, -15, -18, -60, -60],
            mixer: [-10, -11, -24, -25, -60, -60, -60, -60])
        state.peaksHeld = state.peaks
        var max_ = state.peaks
        max_.inputs[2] = 0
        state.peaksMax = max_
        state.visiblePairLabels = Set(state.physicalOutputGroups.prefix(3).map(\.label))
        state.routes[0] = .m1
        state.routes[1] = .m2
        state.routes[2] = .m3
        state.routes[3] = .m4
        state.userSetMixAppearance(tab: 0, name: "Main Mix", colorHex: "#4D8CF2")
        state.userSetMixAppearance(tab: 2, name: "Laura Mix", colorHex: "#4DCC66")
        state.userSetMixAppearance(tab: 4, name: "Rosa Mix", colorHex: "#F2594D")
        return state
    }

    // MARK: - Rendering

    private func render(_ view: some View, to url: URL, scale: CGFloat) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage, "nothing rendered for \(url.lastPathComponent)")
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: url)
    }
}
