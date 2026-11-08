import SwiftUI
import ScarlettCore

/// A vertical mixer strip for one matrix channel in the currently selected bus.
/// Layout mirrors Focusrite Control 2: name + source + colored underline at top,
/// fader with dB scale and meter in the middle, M/S buttons at the bottom.
///
/// For a stereo-linked pair, `channel` is the left channel and the strip is
/// one wide card for both: one name, source, fader and mute/solo, two meters,
/// and the link button between mute and solo.
@MainActor
struct ChannelStrip: View {
    let channel: Int
    @Bindable var state: MixerState
    @Environment(\.faderHeight) private var faderHeight
    @State private var editingName: Bool = false
    @State private var nameDraft: String = ""
    @FocusState private var nameFocused: Bool

    private var stereo: Bool { channel % 2 == 0 && state.isLinked(channel) }
    private var rightSource: SignalSource {
        channel + 1 < state.mixerSources.count ? state.mixerSources[channel + 1] : .off
    }

    var body: some View {
        let source = state.mixerSources[channel]
        let isMuted = state.mixerMutes[channel]
        let isSoloed = state.mixerSolos[channel]

        VStack(spacing: StripLayout.vSpacing) {
            header(source: source)
            Group {
                if stereo {
                    HStack(spacing: 4) {
                        inputSwitch(source: source).frame(maxWidth: .infinity)
                        inputSwitch(source: rightSource).frame(maxWidth: .infinity)
                    }
                } else {
                    inputSwitch(source: source)
                }
            }
            .frame(height: StripLayout.switchRowHeight)
            // Pan (and width, on a stereo-linked pair) only exists for a linked
            // (stereo) mix pair.  The row stays so the faders don't shift
            // between tabs.
            Group {
                if stereo { stereoImageControls } else { panSlider }
            }
                .frame(height: StripLayout.panRowHeight)
                .opacity(panApplies ? 1 : 0)
                .allowsHitTesting(panApplies)
            fader
                .frame(height: faderHeight)
            peakReadout
                .frame(height: StripLayout.peakReadoutHeight)
            mutesolo(isMuted: isMuted, isSoloed: isSoloed)
                .frame(height: StripLayout.controlsHeight)
        }
        .frame(width: stereo ? StripLayout.stereoWidth : StripLayout.width)
        .padding(.vertical, StripLayout.cardPaddingV)
        .padding(.horizontal, 6)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Contextual hardware-input switch
    //
    // When this strip's source is one of the device's software-configurable
    // hardware inputs (per profile.impedanceChannels / hiLoChannels), surface
    // the relevant switch right here on the strip
    // so the user doesn't have to navigate elsewhere.  Otherwise reserve
    // the same vertical space (an empty placeholder) to keep strip heights
    // consistent across the row.

    @ViewBuilder
    private func inputSwitch(source: SignalSource) -> some View {
        switch source {
        case .analog1:
            ImpedanceSwitch(value: Binding(
                get: { state.impedance1 },
                set: { state.userSetImpedance(channel: 1, mode: $0) }
            ))
        case .analog2:
            ImpedanceSwitch(value: Binding(
                get: { state.impedance2 },
                set: { state.userSetImpedance(channel: 2, mode: $0) }
            ))
        case .analog3:
            HiLoSwitch(value: Binding(
                get: { state.hi3 },
                set: { state.userSetHiLo(channel: 3, hi: $0) }
            ))
        case .analog4:
            HiLoSwitch(value: Binding(
                get: { state.hi4 },
                set: { state.userSetHiLo(channel: 4, hi: $0) }
            ))
        default:
            // Reserve the same vertical footprint so every strip aligns.
            Color.clear.frame(height: 22)
        }
    }

    // MARK: - Header

    private func header(source: SignalSource) -> some View {
        VStack(spacing: 3) {
            nameField
            Spacer(minLength: 0)
            if stereo {
                stereoSourcePicker
            } else {
                ThemedMenuPicker(
                    options: state.matrixSourceOptions,
                    displayName: { $0.displayName },
                    selection: Binding(
                        get: { state.mixerSources[channel] },
                        set: { state.userSetMixerSource(channel: channel, source: $0) }
                    )
                )
            }

            Rectangle()
                .fill(source.accentColor)
                .frame(height: 2)
                .padding(.horizontal, 2)
        }
        // Fixed like the pinned strips' headers, so the rows below line up.
        .frame(height: StripLayout.headerHeight, alignment: .bottom)
    }

    private var stereoSourcePicker: some View {
        let choice = state.stereoSourceChoice(leftChannel: channel)
        var options = state.stereoSourceOptions
        if !options.contains(choice) { options.insert(choice, at: 0) }
        return ThemedMenuPicker(
            options: options,
            displayName: { $0.name },
            selection: Binding(
                get: { choice },
                set: { state.userSetStereoSource(leftChannel: channel, to: $0) }
            )
        )
    }

    /// Channel name — defaults to "Ch N" ("Ch N+M" for a stereo pair),
    /// double-click to rename.
    private var nameField: some View {
        let stored = state.mixerNames[channel]
        let fallback = stereo ? "Ch \(channel + 1)+\(channel + 2)" : "Ch \(channel + 1)"
        let displayed = stored.isEmpty ? fallback : stored
        return Group {
            if editingName {
                TextField("Name", text: $nameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .focused($nameFocused)
                    .onSubmit { commitName() }
                    .onExitCommand { editingName = false }
                    .onAppear {
                        nameDraft = stored
                        nameFocused = true
                    }
            } else {
                Text(displayed)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        nameDraft = stored
                        editingName = true
                    }
                    .help("Double-click to rename")
            }
        }
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)
        state.userSetChannelName(channel: channel, name: trimmed)
        editingName = false
    }

    // MARK: - Fader column

    private var fader: some View {
        let busIdx = state.selectedBus.matrixIndex ?? 0
        let level = state.mixLevel(channel: channel, busIdx: busIdx)
        let source = state.mixerSources[channel]

        return HStack(alignment: .center, spacing: 4) {
            VerticalFader(db: Binding(
                get: { level },
                set: { state.userSetMixerLevel(channel: channel, busIdx: busIdx, level: $0) }
            ))
            .opacity(state.mixerMutes[channel] ? 0.4 : 1.0)
            .contextMenu {
                Button("Reset fader to 0 dB") {
                    state.userSetMixerLevel(channel: channel, busIdx: busIdx, level: 0)
                }
            }

            // Reads peaks/peaksHeld/peaksMax internally → isolated from the
            // outer strip body so 20 Hz meter updates only re-render this
            // small view, not the whole strip (faders, pickers, buttons, …).
            StripMeter(state: state, source: source, profile: state.profile)
                .overlay(alignment: .bottom) { if stereo { meterCaption("L") } }
            if stereo {
                StripMeter(state: state, source: rightSource, profile: state.profile)
                    .overlay(alignment: .bottom) { meterCaption("R") }
            }

            DbScale()
        }
        .frame(height: faderHeight)
    }

    /// The L/R captions hang below the meters without taking layout space,
    /// so the meters stay on the shared dB axis.
    private func meterCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize()
            .offset(y: 4)
    }

    private var panApplies: Bool {
        state.isMixPairLinked(MixerState.pairIndex(of: state.selectedBus))
    }

    private var panSlider: some View {
        let pair = MixerState.pairIndex(of: state.selectedBus)
        let pan = state.mixerPans[channel][pair]
        return VStack(spacing: 1) {
            HorizontalSlider(
                value: Binding(
                    get: { pan },
                    set: { state.userSetMixerPan(channel: channel, pair: pair, pan: $0) }
                ),
                range: -1...1,
                origin: 0,
                onReset: { state.userSetMixerPan(channel: channel, pair: pair, pan: 0) }
            )
            .contextMenu {
                Button("Reset pan to center") {
                    state.userSetMixerPan(channel: channel, pair: pair, pan: 0)
                }
            }
            Text(panLabel(pan))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Pan and width for a stereo pair: pan moves the whole image across the
    /// mix, width narrows it toward mono.  Words are left off the sliders; the
    /// ends say what they mean and the value shows while dragging.
    private var stereoImageControls: some View {
        let pair = MixerState.pairIndex(of: state.selectedBus)
        let image = state.stereoPanWidth(leftChannel: channel, pair: pair)
        return VStack(spacing: 0) {
            StereoImageSlider(
                value: Binding(
                    get: { image.pan },
                    set: { state.userSetStereoPan(leftChannel: channel, pair: pair, pan: $0) }),
                range: -1...1,
                origin: 0,
                readout: panLabel(image.pan),
                help: "Pan: moves this stereo pair across the mix. At the far end both channels play on that side. Double-click to center.",
                resetTitle: "Reset pan to center",
                reset: { state.userSetStereoPan(leftChannel: channel, pair: pair, pan: 0) },
                leading: { EndCaption("L") },
                trailing: { EndCaption("R") })
            StereoImageSlider(
                value: Binding(
                    get: { image.width },
                    set: { state.userSetStereoWidth(leftChannel: channel, pair: pair, width: $0) }),
                range: 0...1,
                readout: "\(Int((image.width * 100).rounded()))",
                help: "Width: narrows this stereo pair toward mono. It has no effect with the pair panned fully to one side. Double-click for 100.",
                resetTitle: "Reset width to 100",
                reset: { state.userSetStereoWidth(leftChannel: channel, pair: pair, width: 1) },
                leading: { DotsIcon(count: 1) },
                trailing: { DotsIcon(count: 2) })
                .disabled(abs(image.pan) > 0.999)
        }
    }

    private func panLabel(_ pan: Double) -> String {
        if abs(pan) < 0.02 { return "C" }
        let pct = Int(round(abs(pan) * 100))
        return pan < 0 ? "L\(pct)" : "R\(pct)"
    }

    private var peakReadout: some View {
        let source = state.mixerSources[channel]
        let busIdx = state.selectedBus.matrixIndex ?? 0
        return StripReadout(
            state: state,
            faderDb: state.mixLevel(channel: channel, busIdx: busIdx),
            faderMuted: state.mixerMutes[channel],
            maxPeak: { [stereo, rightSource] s in
                let left = StripMeter.level(from: s.peaksMax, source: source, profile: s.profile)
                guard stereo else { return left }
                return max(left, StripMeter.level(from: s.peaksMax, source: rightSource, profile: s.profile))
            },
            resetHelp: stereo ? "Click to reset this pair's max peaks" : "Click to reset this channel's max peak"
        ) {
            state.clearMaxPeak(forSource: source)
            if stereo { state.clearMaxPeak(forSource: rightSource) }
        }
    }

    // MARK: - Mute / Solo

    private func mutesolo(isMuted: Bool, isSoloed: Bool) -> some View {
        HStack(spacing: 3) {
            Spacer(minLength: 0)
            StripButton(letter: "M", active: isMuted, activeColor: Theme.muteActive) {
                state.userToggleMixerMute(channel: channel)
            }
            // A stereo pair carries its link button between mute and solo; for
            // two separate strips it sits in the gap between them instead
            // (see `MatrixMixerView.channelStrips`).
            if stereo {
                LinkButton(active: true) { state.userToggleLink(channel: channel) }
            }
            StripButton(letter: "S", active: isSoloed, activeColor: Theme.soloActive) {
                state.userToggleMixerSolo(channel: channel)
            }
            Spacer(minLength: 0)
        }
    }

}

/// A slider with a short caption at each end, which swaps to the value while
/// the slider is being dragged.  The end slots keep their width so the slider
/// doesn't resize underneath the pointer.
private struct StereoImageSlider<Leading: View, Trailing: View>: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Where the track's fill starts: the middle for pan, the left end for width.
    var origin: Double?
    let readout: String
    let help: String
    let resetTitle: String
    let reset: () -> Void
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing
    @State private var dragging = false

    private let slotWidth: CGFloat = 20

    var body: some View {
        HStack(spacing: 3) {
            leading.frame(width: slotWidth, alignment: .trailing)
            HorizontalSlider(value: $value, range: range, origin: origin,
                             onEditingChanged: { dragging = $0 }, onReset: reset)
                .contextMenu { Button(resetTitle, action: reset) }
            Group {
                if dragging {
                    Text(readout)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                } else {
                    trailing
                }
            }
            .frame(width: slotWidth, alignment: .leading)
        }
        .frame(height: StripLayout.panRowHeight / 2)
        .help(help)
    }
}

private struct EndCaption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.textSecondary)
    }
}

/// One dot for mono, two overlapping dots for stereo.
private struct DotsIcon: View {
    let count: Int

    var body: some View {
        HStack(spacing: -2) {
            ForEach(0..<count, id: \.self) { _ in
                Circle()
                    .strokeBorder(Theme.textSecondary, lineWidth: 1)
                    .frame(width: 6, height: 6)
            }
        }
    }
}

/// Compact Line/Instrument toggle for the combo-input strips (Analog 1, 2).
struct ImpedanceSwitch: View {
    @Binding var value: Impedance

    var body: some View {
        Picker("", selection: $value) {
            Text("Line").tag(Impedance.line)
            Text("Inst").tag(Impedance.instrument)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.mini)
        .frame(height: 22)
    }
}

/// Compact Lo/Hi gain toggle for the line-input strips (Analog 3, 4).
struct HiLoSwitch: View {
    @Binding var value: Bool

    var body: some View {
        Picker("", selection: $value) {
            Text("Lo").tag(false)
            Text("Hi").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.mini)
        .frame(height: 22)
    }
}

/// Live + peak-hold + max meter for one strip.  Isolated into its own struct
/// so that 20 Hz `peaks*` updates only re-render this view, not the parent
/// strip's fader / pickers / buttons / name field.
@MainActor
struct StripMeter: View {
    @Bindable var state: MixerState
    let source: SignalSource
    let profile: DeviceProfile

    var body: some View {
        let live = Self.level(from: state.peaks, source: source, profile: profile)
        let held = Self.level(from: state.peaksHeld, source: source, profile: profile)
        let max_ = Self.level(from: state.peaksMax, source: source, profile: profile)
        VerticalMeter(db: live, peakDb: held, maxPeakDb: max_)
    }

    static func level(from peaks: PeakReading, source: SignalSource, profile: DeviceProfile) -> Double {
        let bus = MixBus(rawValue: source.rawValue) ?? .off
        return peaks.level(for: bus, profile: profile)
    }
}

/// The strip's readout row, DAW style: the fader's level on the left (under
/// the fader) and the meter's max peak since the last reset on the right
/// (under the meter).  Click the max peak to reset it; at full scale it
/// reads "CLIP" in red, held until the reset.  Reads the peaks itself, so
/// 20 Hz meter updates re-render only this row, not the whole strip.
@MainActor
struct StripReadout: View {
    @Bindable var state: MixerState
    /// The fader's level, or nil for an output without a fader.
    let faderDb: Double?
    var faderMuted = false
    /// The max peak to show, read from `state` (louder side of a pair).
    let maxPeak: (MixerState) -> Double
    let resetHelp: String
    let reset: () -> Void

    var body: some View {
        let peak = maxPeak(state)
        HStack(spacing: 2) {
            // Cubase-style contrast: the fader level bright, the peak dimmer.
            cell(faderDb.map(DbAxis.format) ?? "",
                 color: faderMuted ? Theme.muteActive : Theme.textPrimary)
            Button(action: reset) {
                cell(DbAxis.formatPeak(peak),
                     color: peak >= DbAxis.clip ? Theme.failure : Theme.textSecondary.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help(resetHelp)
        }
    }

    private func cell(_ text: String, color: Color) -> some View {
        ReadoutCell(text: text, color: color)
    }
}

/// One field of a level / peak readout: monospaced figures on a dark
/// inset — the mixer strips' readout row and the menu bar panel.
struct ReadoutCell: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.readoutField)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .contentShape(Rectangle())
    }
}

/// Link button between two neighbouring channels (1+2, 3+4, …) — toggles
/// whether they are one stereo pair.  Active = paired.
struct LinkButton: View {
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "link")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(active ? Theme.muteActive : Theme.panelRaised)
                .foregroundStyle(active ? .white : Theme.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .help(active ? "Stereo pair (click to split into two channels)" : "Link these two channels as a stereo pair")
        .accessibilityLabel(active ? "Split stereo pair" : "Link as stereo pair")
    }
}

struct StripButton: View {
    let letter: String
    let active: Bool
    let activeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(letter)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 26, height: 22)
                .background(active ? activeColor : Theme.panelRaised)
                .foregroundStyle(active ? .white : Theme.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }
}
