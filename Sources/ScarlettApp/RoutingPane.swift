import SwiftUI
import ScarlettCore

enum RoutingTab: CaseIterable, Identifiable {
    case outputs, capture

    var id: Self { self }
    var title: String { self == .outputs ? "Outputs" : "USB capture" }
}

/// The routing page in the analog look: tabs on one plate with a strip for each
/// pair of outputs (or of USB capture channels), laid out like the mixer's.
/// Each strip is routed as one stereo choice, the way the mixer pairs up, with
/// a link key to choose the two sides separately instead.
@MainActor
struct RoutingPane: View {
    @Bindable var state: MixerState
    @State private var tab: RoutingTab
    @State private var blockHeight: CGFloat = 0

    init(state: MixerState, initialTab: RoutingTab = .outputs) {
        self.state = state
        _tab = State(initialValue: initialTab)
    }

    private let tabHeight: CGFloat = 30
    private let openTabHeight: CGFloat = 38

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Routing").font(.title3).bold().foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(hint)
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 440, alignment: .trailing)
                }

                VStack(spacing: 0) {
                    tabsRow
                        .zIndex(1)
                    panel
                }
                .coordinateSpace(name: "routeBlock")
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { blockHeight = $0 }
                .backgroundPreferenceValue(OpenTabFrameKey.self) { frame in
                    MixPlate(tab: frame, tabHeight: openTabHeight, glow: Theme.tabOutline)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("The app reads the capture routing from the interface. Output routing is remembered by the app and sent again at launch.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if tab == .capture {
                        Button("Reset to straight-through") { state.resetCaptureRoutesToFactory() }
                            .disabled(!state.captureDiffersFromFactory)
                            .help("Send every USB capture channel its own input again: Analog 1+2 on DAW inputs 1+2, and so on.")
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
    }

    private var hint: String {
        switch tab {
        case .outputs:
            return "Pick what feeds each pair of outputs. Link keys choose left and right together; unlink a pair to choose its two sides separately."
        case .capture:
            return "Pick what your DAW records on each pair of its inputs. Out of the box each one hears its own input, so Analog 1+2 arrives in the DAW as inputs 1+2."
        }
    }

    // MARK: - Targets

    private var targets: [RouteTarget] {
        switch tab {
        case .outputs:
            return state.physicalOutputGroups
                .filter { group in group.outputs.contains { $0.isLeft } && group.outputs.contains { !$0.isLeft } }
                .map { .output(label: $0.label) }
        case .capture:
            let channels = state.profile.captureChannelCount + state.profile.loopbackChannelCount
            return (0..<(channels / 2)).map { .capture(pair: $0) }
        }
    }

    // MARK: - Tabs

    private var tabsRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(RoutingTab.allCases) { tabButton($0) }
            Spacer(minLength: 0)
        }
        .frame(height: openTabHeight, alignment: .bottom)
        .animation(.easeInOut(duration: 0.18), value: tab)
    }

    private func tabButton(_ kind: RoutingTab) -> some View {
        let selected = tab == kind
        return Button {
            tab = kind
        } label: {
            Text(kind.title)
                .font(.system(size: selected ? 13 : 11.5, weight: .semibold))
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: selected ? 150 : 132, height: selected ? openTabHeight : tabHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
        .background {
            // The open tab has no face of its own: it is part of the plate drawn
            // behind the whole block (`MixPlate`).
            if !selected { AnalogTabFace(selected: false) }
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: OpenTabFrameKey.self,
                                       value: selected ? geo.frame(in: .named("routeBlock")) : nil)
            }
        }
        .overlay(alignment: .top) {
            if selected { TabGlowLine(color: Theme.tabOutline, selected: true) }
        }
        .padding(.trailing, 8)
        .zIndex(selected ? 1 : 0)
    }

    // MARK: - Panel

    private var panel: some View {
        let list = targets
        return StripScroller(
            ids: Array(list.indices),
            size: { _ in 1 },
            noun: tab == .outputs ? "output" : "capture pair",
            blockSpace: "routeBlock", blockHeight: blockHeight, tabRowHeight: openTabHeight
        ) { index in
            RoutingStrip(state: state, target: list[index])
        }
        .id(tab)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }
}

// MARK: - Strip

/// One pair of outputs, or of USB capture channels, and what feeds it.
@MainActor
struct RoutingStrip: View {
    @Bindable var state: MixerState
    let target: RouteTarget
    @State private var renaming = false

    static let width: CGFloat = 132
    private let meterHeight: CGFloat = 190

    var body: some View {
        let linked = state.isRoutePairLinked(target)
        VStack(spacing: StripLayout.vSpacing) {
            header
            RouteLinkKey(linked: linked) { state.userSetRoutePairLinked(target, linked: !linked) }
            pickers(linked: linked)
                .frame(height: 58)
            meters
        }
        .frame(width: Self.width)
        .padding(.vertical, StripLayout.cardPaddingV)
        .padding(.horizontal, 6)
        .stripCard()
    }

    // MARK: Header

    private var title: String {
        switch target {
        case .output(let label): return state.outputDisplayName(label: label)
        case .capture(let pair): return "DAW in \(pair * 2 + 1)+\(pair * 2 + 2)"
        }
    }

    private var subtitle: String {
        switch target {
        case .output(let label):
            let outputs = state.physicalOutputGroups.first { $0.label == label }?.outputs ?? []
            return "Out " + outputs.map { "\($0.wValue + 1)" }.joined(separator: "+")
        case .capture(let pair):
            return "Capture \(pair * 2 + 1)–\(pair * 2 + 2)"
        }
    }

    private var iconName: String {
        switch target {
        case .output(let label): return OutputKind(label: label).icon
        case .capture: return "arrow.down.to.line"
        }
    }

    private var iconColor: Color {
        switch target {
        case .output(let label): return OutputKind(label: label).color
        case .capture: return Theme.accentPlayback
        }
    }

    private var header: some View {
        VStack(spacing: 3) {
            icon
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 4) {
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                if !state.isRouteAtFactory(target) {
                    Circle()
                        .fill(Theme.muteActive)
                        .frame(width: 5, height: 5)
                        .help("Differs from the factory setup (\(state.factoryRouteName(target) ?? "its own input")).")
                        .accessibilityLabel("Differs from the factory setup")
                }
            }
            Rectangle()
                .fill(state.routeColor(for: target) ?? Theme.textSecondary.opacity(0.5))
                .frame(height: 2)
                .padding(.horizontal, 2)
                .padding(.top, 2)
        }
        .frame(height: 78, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: state.routeSides(target).left)
    }

    @ViewBuilder
    private var icon: some View {
        let glyph = Image(systemName: iconName)
            .font(.system(size: 20))
            .foregroundStyle(iconColor)
            .shadow(color: iconColor.opacity(0.55), radius: 4)
            .frame(height: 28)
        if case .output(let label) = target {
            Button { renaming = true } label: { glyph.frame(maxWidth: .infinity).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .cursor(.pointingHand)
                .help("Click to rename this output")
                .popover(isPresented: $renaming, arrowEdge: .bottom) {
                    OutputAppearanceEditor(
                        label: label, name: state.outputNames[label] ?? "",
                        colorHex: state.outputColorHex(label: label), showsColor: false
                    ) { name, _ in state.userSetOutputName(label: label, name: name) }
                }
        } else {
            glyph
        }
    }

    // MARK: Pickers

    @ViewBuilder
    private func pickers(linked: Bool) -> some View {
        if linked {
            pairPicker
        } else {
            VStack(spacing: 6) {
                sidePicker(letter: "L", isLeft: true)
                sidePicker(letter: "R", isLeft: false)
            }
        }
    }

    /// One choice for both sides.
    private var pairPicker: some View {
        let current = state.routeChoice(for: target)
        let options = state.routeChoiceOptions
        let mixes = options.filter { if case .mixPair = $0 { return true } else if case .monoMix = $0 { return true } else { return false } }
        let sources = options.filter { if case .sourcePair = $0 { return true } else { return false } }
        let binding = Binding(get: { current }, set: { state.userSetRouteChoice($0, for: target) })
        return Menu {
            Picker("", selection: binding) {
                if case .custom = current { Text(state.routeChoiceName(current)).tag(current) }
                Text("Off").tag(RouteChoice.off)
                Section("Mixes") { ForEach(mixes) { Text(state.routeChoiceName($0)).tag($0) } }
                Section("Stereo sources") { ForEach(sources) { Text(state.routeChoiceName($0)).tag($0) } }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            RoutePickerLabel(text: state.routeChoiceName(current))
        }
        .routePickerStyle()
    }

    /// One side on its own.
    private func sidePicker(letter: String, isLeft: Bool) -> some View {
        let sides = state.routeSides(target)
        let bus = isLeft ? sides.left : sides.right
        let binding = Binding(get: { bus }, set: { new in
            state.setRouteSides(target, left: isLeft ? new : sides.left, right: isLeft ? sides.right : new)
        })
        return HStack(spacing: 4) {
            Text(letter)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 8)
            Menu {
                Picker("", selection: binding) {
                    Text("Off").tag(MixBus.off)
                    ForEach(state.routeSideGroups, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.buses) { Text(state.routeSideName($0)).tag($0) }
                        }
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                RoutePickerLabel(text: bus == .off ? "Off" : state.routeSideName(bus))
            }
            .routePickerStyle()
        }
    }

    // MARK: Meters

    /// What is arriving at the pair now.
    private var meters: some View {
        let sides = state.routeSides(target)
        return HStack(alignment: .top, spacing: 4) {
            RoutedMeter(state: state, source: sides.left, profile: state.profile)
            RoutedMeter(state: state, source: sides.right, profile: state.profile)
            DbScale(axis: .attenuation)
        }
        .environment(\.faderHeight, meterHeight)
        .frame(height: meterHeight)
    }
}

// MARK: - Pieces

/// What a routing picker shows: the name of what's routed.  (The colour of it is
/// the strip's underline: a menu button only draws text and images.)
private struct RoutePickerLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 2)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Theme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

private extension View {
    func routePickerStyle() -> some View {
        menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(maxWidth: .infinity)
    }
}

/// The key between a strip's header and its pickers: lit while the two sides
/// follow one choice.
private struct RouteLinkKey: View {
    let linked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "link")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(linked ? Color.white : Theme.textSecondary)
                .frame(width: 26, height: 20)
                .analogKey(active: linked, color: Theme.muteActive, cornerRadius: 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(AnalogKeyPressStyle())
        .help(linked
              ? "Left and right follow one choice. Click to choose them separately."
              : "Left and right are chosen separately. Click to link them.")
        .accessibilityLabel(linked ? "Choose left and right separately" : "Link left and right")
    }
}
