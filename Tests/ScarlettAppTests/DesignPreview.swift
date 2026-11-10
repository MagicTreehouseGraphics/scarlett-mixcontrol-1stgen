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
        try renderWindow(page(state, spare: 0), size: CGSize(width: 2500, height: 780),
                         to: dir.appendingPathComponent("page-wide.png"))
        try renderWindow(page(sampleState(profile: .scarlett18i20), spare: 0), size: CGSize(width: 1500, height: 780),
                         to: dir.appendingPathComponent("page-18i20.png"))
        state.selectedBus = state.matrixBuses[2]
        try renderWindow(page(state, spare: 140), size: CGSize(width: 1500, height: 780),
                         to: dir.appendingPathComponent("page-second.png"))
        state.selectedBus = state.matrixBuses[0]
        try contactSheet(state, to: dir.appendingPathComponent("colours.png"))
        appearance.look = .classic
        try renderWindow(page(state, spare: 140), size: CGSize(width: 1500, height: 780),
                         to: dir.appendingPathComponent("page-classic.png"))
    }

    /// The top-left of the page with the first mix in each of several colours,
    /// stacked, to compare how the glow looks in each.
    private func contactSheet(_ state: MixerState, to url: URL) throws {
        let colours = ["", "#F2C94C", "#F5963A", "#F2594D", "#4DCC66", "#9B6BF2"]
        let crop = CGSize(width: 760, height: 250)
        let sheet = NSImage(size: CGSize(width: crop.width, height: crop.height * CGFloat(colours.count)))
        let size = CGSize(width: 1500, height: 780)
        var images: [NSBitmapImageRep] = []
        for hex in colours {
            state.userSetMixAppearance(tab: 0, name: "Main Mix", colorHex: hex)
            images.append(try snapshot(page(state, spare: 0), size: size))
        }
        state.userSetMixAppearance(tab: 0, name: "Main Mix", colorHex: "#4D8CF2")
        sheet.lockFocus()
        for (i, rep) in images.enumerated() {
            let y = crop.height * CGFloat(colours.count - 1 - i)
            let source = NSRect(x: 0, y: size.height - crop.height, width: crop.width, height: crop.height)
            NSImage(cgImage: rep.cgImage!, size: size)
                .draw(in: NSRect(x: 0, y: y, width: crop.width, height: crop.height), from: source,
                      operation: .copy, fraction: 1)
        }
        sheet.unlockFocus()
        let tiff = try XCTUnwrap(sheet.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    /// Rough cost of redrawing the whole page as a live window resize does: one
    /// layout and draw per window height.  Run with RENDER_BENCH=1.
    func testResizeCost() throws {
        guard ProcessInfo.processInfo.environment["RENDER_BENCH"] != nil else {
            throw XCTSkip("Set RENDER_BENCH=1 to time page redraws")
        }
        _ = NSApplication.shared
        let state = sampleState()
        let appearance = AppearanceSettings.shared
        let saved = (appearance.look, appearance.meterGlow)
        defer { (appearance.look, appearance.meterGlow) = saved }

        let heights = stride(from: 780, through: 640, by: -10).map { CGFloat($0) }
        func time(_ name: String, look: MixerLook, glow: MeterGlow = .full, spare: CGFloat = 0) throws {
            appearance.look = look
            appearance.meterGlow = glow
            let host = NSHostingView(rootView: MatrixMixerView(state: state)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.background)
                .environment(\.faderHeight, 300))
            host.frame = CGRect(x: 0, y: 0, width: 1500, height: 780)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            for _ in 0..<4 { RunLoop.current.run(until: Date().addingTimeInterval(0.05)); host.layoutSubtreeIfNeeded() }
            var total = 0.0
            for (i, h) in heights.enumerated() {
                host.rootView = host.rootView   // keep the type; the size change drives the redraw
                host.frame = CGRect(x: 0, y: 0, width: 1500, height: h)
                let start = Date()
                host.layoutSubtreeIfNeeded()
                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                if i > 0 { total += Date().timeIntervalSince(start) * 1000 }
            }
            print("RESIZE \(name): \(String(format: "%.1f", total / Double(heights.count - 1))) ms per step")
        }
        try time("classic", look: .classic)
        try time("analog", look: .analog)
        try time("analog simple meters", look: .analog, glow: .simple)
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
        let rep = try snapshot(view, size: size)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    private func snapshot(_ view: some View, size: CGSize) throws -> NSBitmapImageRep {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI settle: measured sizes and onAppear work arrive on later passes.
        for _ in 0..<20 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            host.layoutSubtreeIfNeeded()
        }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
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
                VerticalFader(db: .constant(-8), axis: .attenuation, tint: Color(hex: "#F2594D"))
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

    private func sampleState(profile: DeviceProfile = .scarlett8i6) -> MixerState {
        let state = MixerState(autoConnect: false, profile: profile)
        let sources: [SignalSource] = profile == .scarlett8i6
            ? [.analog1, .analog2, .analog3, .analog4, .daw3, .daw4, .spdif1, .spdif2, .daw5, .daw6]
            : [.analog1, .analog2, .analog3, .analog4, .analog5, .analog6, .analog7, .analog8,
               .spdif1, .spdif2, .adat1, .adat2, .adat3, .adat4, .adat5, .adat6, .adat7, .adat8]
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
