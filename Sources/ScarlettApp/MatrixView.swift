import SwiftUI
import ScarlettCore

/// The matrix mixer view — Control 2 style.
///
/// Top: mix tabs (M1..Mn) in the style of folder tabs, grouped in pairs with
/// a link button between the two mixes of each.  The selected tab joins the
/// panel below it, so it is clear which mix the strips belong to.
/// In the panel: horizontally scrolling row of `ChannelStrip`s, one per matrix
/// channel we expose.  We show at least 14 (the 8i6-era default), and expand
/// to cover every physical input on devices that have more — the 18i6/18i8/
/// 18i20 have 18 real inputs, so all 18 matrix slots are useful there.
@MainActor
struct MatrixMixerView: View {
    @Bindable var state: MixerState
    /// The pair the user asked to relink while its two mixes still differ;
    /// held until they confirm that M-right will be overwritten.
    @State private var pendingRelink: Int?
    /// The mix tab (see `MixerState.mixTabKey`) whose name and colour are
    /// being edited in a popover.
    @State private var customizing: Int?
    /// Height of the tab row and panel together, which the edge keys need to
    /// take the panel's grey at their height.
    @State private var blockHeight: CGFloat = 0
    private var visibleChannels: Range<Int> {
        let physicalInputs = state.profile.sources.filter {
            $0.category == .analog || $0.category == .digital
        }.count
        return 0..<min(state.profile.matrixInputCount, max(14, physicalInputs))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            // The outputs panel runs alongside the tabs and the mix panel, and
            // the two sides share one height.
            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: 0) {
                    tabsRow
                        .zIndex(1)
                    mixPanel
                }
                .coordinateSpace(name: "mixBlock")
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { blockHeight = $0 }
                .backgroundPreferenceValue(OpenTabFrameKey.self) { tab in
                    if AppearanceSettings.shared.look == .analog {
                        MixPlate(tab: tab, tabHeight: openTabHeight,
                                 glow: tabColor(tabKey(state.selectedBus)) ?? Theme.tabOutline)
                    }
                }
                OutputsPanel(state: state)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog(
            relinkTitle, isPresented: Binding(
                get: { pendingRelink != nil },
                set: { if !$0 { pendingRelink = nil } }),
            titleVisibility: .visible
        ) {
            Button("Link and overwrite", role: .destructive) {
                if let pair = pendingRelink { state.userSetMixPairLinked(pair, linked: true) }
                pendingRelink = nil
            }
            Button("Cancel", role: .cancel) { pendingRelink = nil }
        } message: {
            Text("The right mix takes the left mix's levels for every channel, and its own levels are replaced.")
        }
    }

    private var relinkTitle: String {
        guard let pair = pendingRelink else { return "" }
        return "Link M\(pair * 2 + 1) and M\(pair * 2 + 2)?"
    }

    /// A tab's height when it is the open one, and when it isn't.  The open
    /// tab rises above the rest and the others sit a little smaller, so it is
    /// clear which is which.
    private let tabHeight: CGFloat = 30
    private let openTabHeight: CGFloat = 38
    private func tabH(_ selected: Bool) -> CGFloat { selected ? openTabHeight : tabHeight }

    private func tabKey(_ bus: MixBus) -> Int { state.mixTabKey(forBus: bus.matrixIndex ?? 0) }
    private func tabColor(_ key: Int) -> Color? { Color(hex: state.mixColorHex(forTab: key)) }

    /// The tab or tabs of one mix pair.  Linked, M-left, the link and M-right
    /// are one wide tab; unlinked, they are two tabs with the link between.
    @ViewBuilder
    private func mixPairTabs(_ pair: Int) -> some View {
        let left = state.matrixBuses[pair * 2]
        let right = state.matrixBuses[pair * 2 + 1]
        let pairName = "M\(pair * 2 + 1)+M\(pair * 2 + 2)"
        Group {
            if state.isMixPairLinked(pair) {
                let selected = state.selectedBus == left || state.selectedBus == right
                let name = state.mixName(forTab: pair * 2)
                mixTab(selected: selected, key: pair * 2, title: pairName,
                       placeholder: "Mix \(pairName)") {
                    HStack(spacing: 0) {
                        if name.isEmpty {
                            tabLabel(left, selected: selected)
                            mixLinkButton(pair: pair, linked: true)
                                .padding(.horizontal, 6)
                            tabLabel(right, selected: selected)
                        } else {
                            namedLabel(name, caption: pairName, bus: left, selected: selected, width: 126)
                            mixLinkButton(pair: pair, linked: true)
                                .padding(.horizontal, 6)
                        }
                        copyArrow(for: right, selected: selected)
                    }
                }
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    monoTab(left)
                    mixLinkButton(pair: pair, linked: false)
                        .padding(.bottom, (tabHeight - 20) / 2)
                    monoTab(right)
                }
            }
        }
        .padding(.trailing, 20)
    }

    private func monoTab(_ bus: MixBus) -> some View {
        let selected = state.selectedBus == bus
        let key = tabKey(bus)
        let name = state.mixName(forTab: key)
        return mixTab(selected: selected, key: key, title: "M\(key + 1)", placeholder: bus.displayName) {
            HStack(spacing: 0) {
                if name.isEmpty {
                    tabLabel(bus, selected: selected)
                } else {
                    namedLabel(name, caption: "M\(key + 1)", bus: bus, selected: selected, width: 84)
                }
                copyArrow(for: bus, selected: selected)
            }
        }
    }

    /// A folder tab around `content`.  Selected, it has the panel's fill and an
    /// outline that opens into the panel's border; otherwise it is a plain
    /// block resting on the panel's top edge.  A colour the user gave the mix
    /// tints the outline and marks the tab with a stripe.  The menu's
    /// "Name & color…" opens the editor.
    private func mixTab<Content: View>(selected: Bool, key: Int, title: String, placeholder: String,
                                       @ViewBuilder content: () -> Content) -> some View {
        let lineWidth: CGFloat = 1.5
        let accent = tabColor(key)
        let analog = AppearanceSettings.shared.look == .analog
        return content()
            .frame(height: tabH(selected))
            .background {
                if analog {
                    // The open tab has no face of its own: it is part of the
                    // plate drawn behind the whole block (`MixPlate`).
                    if !selected { AnalogTabFace(selected: false) }
                } else {
                    FolderTabShape().fill(selected ? Theme.tabPanel : Theme.panelRaised)
                }
            }
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: OpenTabFrameKey.self,
                        value: analog && selected ? geo.frame(in: .named("mixBlock")) : nil)
                }
            }
            .overlay(alignment: .top) {
                // The mix's colour as a lit line along the top: bright and
                // glowing on the open tab, dimmer on the others (where it
                // only shows for a colour the user chose).
                if analog, selected || accent != nil {
                    TabGlowLine(color: accent ?? Theme.tabOutline, selected: selected)
                }
            }
            .overlay {
                if !analog, let accent {
                    Rectangle().fill(accent)
                        .frame(height: 3)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .mask(FolderTabShape())
                }
            }
            .overlay {
                if !analog, selected {
                    FolderTabShape(inset: lineWidth / 2, overhang: lineWidth)
                        .stroke(accent ?? Theme.tabOutline, lineWidth: lineWidth)
                }
            }
            .overlay(alignment: .bottom) {
                // Hides the panel's top border under the tab.
                if selected && !analog {
                    Rectangle()
                        .fill(Theme.tabPanel)
                        .frame(height: lineWidth * 2)
                        .padding(.horizontal, lineWidth)
                        .offset(y: lineWidth)
                }
            }
            .zIndex(selected ? 1 : 0)
            .popover(isPresented: Binding(
                get: { customizing == key },
                set: { if !$0, customizing == key { customizing = nil } }
            ), arrowEdge: .bottom) {
                MixAppearanceEditor(
                    title: title, placeholder: placeholder,
                    name: state.mixName(forTab: key), colorHex: state.mixColorHex(forTab: key)
                ) { name, hex in
                    state.userSetMixAppearance(tab: key, name: name, colorHex: hex)
                }
            }
    }

    private func tabLabel(_ bus: MixBus, selected: Bool) -> some View {
        Button {
            state.selectedBus = bus
        } label: {
            Text(bus.displayName)
                .font(.system(size: selected ? 13 : 11.5, weight: .semibold))
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: selected ? 66 : 58, height: tabH(selected))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
        .contextMenu { copyMixMenuItems(for: bus) }
    }

    /// A tab label with the user's name, and which mixes it is beneath.
    private func namedLabel(_ name: String, caption: String, bus: MixBus, selected: Bool,
                            width: CGFloat) -> some View {
        Button {
            state.selectedBus = bus
        } label: {
            VStack(spacing: 0) {
                Text(name)
                    .font(.system(size: selected ? 12 : 10.5, weight: .semibold))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(caption)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 6)
            .frame(width: width, height: tabH(selected))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
        .contextMenu { copyMixMenuItems(for: bus) }
    }

    /// The copy dropdown's arrow, in its own roomy segment behind a thin
    /// divider at the end of a tab.
    private func copyArrow(for bus: MixBus, selected: Bool) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 4, height: tabH(selected))
            Rectangle()
                .fill(selected ? Theme.tabOutline.opacity(0.5) : Color.black.opacity(0.35))
                .frame(width: 1, height: 18)
            Menu {
                copyMixMenuItems(for: bus)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    .frame(width: 32, height: tabH(selected))
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Copy this mix to another")
        }
    }

    /// The button between a pair's two mixes, inside the wide tab when linked
    /// and between the two tabs when not.  Lit blue while linked, like the
    /// link button between two channels.
    private func mixLinkButton(pair: Int, linked: Bool) -> some View {
        let name = "M\(pair * 2 + 1) and M\(pair * 2 + 2)"
        return Button {
            toggleMixLink(pair)
        } label: {
            Image(systemName: "link")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(linked ? Color.white : Theme.textSecondary)
                .frame(width: 24, height: 20)
                .analogKey(active: linked, color: Theme.muteActive, cornerRadius: 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(AnalogKeyPressStyle())
        .help(linked
              ? "\(name) are one stereo mix. Click to split them into two mono mixes."
              : "\(name) are two mono mixes. Click to link them as one stereo mix.")
        .accessibilityLabel(linked ? "Unlink \(name)" : "Link \(name)")
    }

    private func toggleMixLink(_ pair: Int) {
        if state.isMixPairLinked(pair) {
            state.userSetMixPairLinked(pair, linked: false)
        } else if state.relinkingOverwrites(pair: pair) {
            pendingRelink = pair
        } else {
            state.userSetMixPairLinked(pair, linked: true)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Mixer").font(.title3).bold().foregroundStyle(Theme.textPrimary)
            Spacer()
            toolbar
        }
    }

    private var tabsRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(0..<state.stereoPairCount, id: \.self) { pair in
                mixPairTabs(pair)
            }
            Spacer(minLength: 0)
        }
        .frame(height: openTabHeight, alignment: .bottom)
        .animation(.easeInOut(duration: 0.18), value: state.selectedBus)
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            FeedbackButton(action: { state.clearMaxPeaks(); return true }) { phase in
                FeedbackPill(phase: phase, icon: "arrow.counterclockwise",
                             title: "Clear peaks", doneTitle: "Cleared")
            }
            .buttonStyle(.pill)
            .fixedSize()
            .help("Reset the red max-peak tick on every strip.")

            MasterMuteButton(state: state)

            FeedbackButton(action: { await state.saveToFlash() }) { phase in
                FeedbackPill(phase: phase, icon: "internaldrive",
                             title: "Save to hardware", doneTitle: "Saved")
            }
            .buttonStyle(.pill)
            .fixedSize()
            .disabled(!state.isConnected)
            .help("Persist current settings to device flash so they survive a power cycle.")

        }
    }

    /// The copy options for a bus tab, in its dropdown and right-click menu.  A
    /// linked pair copies to other pairs; a mono mix copies to other mono mixes.
    @ViewBuilder
    private func copyMixMenuItems(for bus: MixBus) -> some View {
        let busIdx = bus.matrixIndex ?? 0
        let pair = busIdx / 2
        let pairLabel: (Int) -> String = { "M\($0 * 2 + 1)+M\($0 * 2 + 2)" }
        Button("Name & color…") { customizing = state.mixTabKey(forBus: busIdx) }
        Divider()
        if state.isMixPairLinked(pair) {
            Section("Copy \(pairLabel(pair)) to") {
                ForEach(state.pairCopyTargets(fromPair: pair), id: \.self) { dest in
                    Button(pairLabel(dest)) { state.userCopyMixPair(from: pair, to: dest) }
                }
            }
        } else {
            let targets = state.mixCopyTargets(fromBus: busIdx)
            Section("Copy \(bus.displayName) to") {
                if targets.isEmpty {
                    Text("No other mono mixes")
                }
                ForEach(targets, id: \.self) { dest in
                    Button(state.matrixBuses[dest].displayName) { state.userCopyMix(from: busIdx, to: dest) }
                }
                if (0..<state.stereoPairCount).contains(where: { state.isMixPairLinked($0) }) {
                    Text("Linked pairs can't take a single mix")
                }
            }
        }
    }

    /// Channels `left` and `left + 1`: one wide stereo strip when linked,
    /// otherwise two strips with the link button between them.
    @ViewBuilder
    private func channelStrips(startingAt left: Int) -> some View {
        if left + 1 >= visibleChannels.upperBound || state.isLinked(left) {
            ChannelStrip(channel: left, state: state)
        } else {
            HStack(spacing: 6) {
                ChannelStrip(channel: left, state: state)
                ChannelStrip(channel: left + 1, state: state)
            }
            .overlay(alignment: .bottom) {
                // Level with the strips' mute/solo row.
                LinkButton(active: false) { state.userToggleLink(channel: left) }
                    .padding(.bottom, StripLayout.cardPaddingV)
            }
        }
    }

    /// The panel under the tabs: the channel strips and the DAW return, which
    /// belong to the selected mix.  The output strips beside it belong to all.
    private var mixPanel: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 6,
                                           bottomTrailingRadius: 6, topTrailingRadius: 6)
        let outline = tabColor(tabKey(state.selectedBus)) ?? Theme.tabOutline
        let analog = AppearanceSettings.shared.look == .analog
        return HStack(alignment: .top, spacing: 6) {
            StripScroller(
                ids: Array(stride(from: visibleChannels.lowerBound, to: visibleChannels.upperBound, by: 2)),
                size: { min(2, visibleChannels.upperBound - $0) },
                noun: "channel",
                blockSpace: "mixBlock", blockHeight: blockHeight, tabRowHeight: openTabHeight
            ) { left in
                channelStrips(startingAt: left)
            }
            if state.hasPinnedDawReturn {
                PinnedDawStrip(state: state)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .environment(\.mixGlowColor, analog ? outline : nil)
        .animation(.easeInOut(duration: 0.25), value: state.selectedBus)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            // In the analog look the plate behind the whole block draws it.
            if !analog { shape.fill(Theme.tabPanel) }
        }
        .overlay {
            if !analog { shape.strokeBorder(outline, lineWidth: 1.5) }
        }
    }
}
