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
    private var visibleChannels: Range<Int> {
        let physicalInputs = state.profile.sources.filter {
            $0.category == .analog || $0.category == .digital
        }.count
        return 0..<min(state.profile.matrixInputCount, max(14, physicalInputs))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            VStack(spacing: 0) {
                tabsRow
                    .zIndex(1)
                HStack(alignment: .top, spacing: 6) {
                    mixPanel
                    PinnedMasterStrip(state: state)
                }
            }
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

    private let tabHeight: CGFloat = 32

    /// The tab or tabs of one mix pair.  Linked, M-left, the link and M-right
    /// are one wide tab; unlinked, they are two tabs with the link between.
    @ViewBuilder
    private func mixPairTabs(_ pair: Int) -> some View {
        let left = state.matrixBuses[pair * 2]
        let right = state.matrixBuses[pair * 2 + 1]
        Group {
            if state.isMixPairLinked(pair) {
                let selected = state.selectedBus == left || state.selectedBus == right
                mixTab(selected: selected) {
                    HStack(spacing: 0) {
                        tabLabel(left, selected: selected)
                        mixLinkButton(pair: pair, linked: true)
                            .padding(.horizontal, 6)
                        tabLabel(right, selected: selected)
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
        return mixTab(selected: selected) {
            HStack(spacing: 0) {
                tabLabel(bus, selected: selected)
                copyArrow(for: bus, selected: selected)
            }
        }
    }

    /// A folder tab around `content`.  Selected, it has the panel's fill and a
    /// blue outline that opens into the panel's border; otherwise it is a
    /// plain block resting on the panel's top edge.
    private func mixTab<Content: View>(selected: Bool, @ViewBuilder content: () -> Content) -> some View {
        let lineWidth: CGFloat = 1.5
        return content()
            .frame(height: tabHeight)
            .background(FolderTabShape().fill(selected ? Theme.tabPanel : Theme.panelRaised))
            .overlay {
                if selected {
                    FolderTabShape(inset: lineWidth / 2, overhang: lineWidth)
                        .stroke(Theme.tabOutline, lineWidth: lineWidth)
                }
            }
            .overlay(alignment: .bottom) {
                // Hides the panel's top border under the tab.
                if selected {
                    Rectangle()
                        .fill(Theme.tabPanel)
                        .frame(height: lineWidth * 2)
                        .padding(.horizontal, lineWidth)
                        .offset(y: lineWidth)
                }
            }
            .zIndex(selected ? 1 : 0)
    }

    private func tabLabel(_ bus: MixBus, selected: Bool) -> some View {
        Button {
            state.selectedBus = bus
        } label: {
            Text(bus.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 60, height: tabHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { copyMixMenuItems(for: bus) }
    }

    /// The copy dropdown's arrow, in its own roomy segment behind a thin
    /// divider at the end of a tab.
    private func copyArrow(for bus: MixBus, selected: Bool) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 4, height: tabHeight)
            Rectangle()
                .fill(selected ? Theme.tabOutline.opacity(0.5) : Color.black.opacity(0.35))
                .frame(width: 1, height: 18)
            Menu {
                copyMixMenuItems(for: bus)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    .frame(width: 32, height: tabHeight)
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
                .background(linked ? Theme.muteActive : Theme.panelRaised)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

            outputsMenu
                .help("Choose which output pairs are pinned as strips on the right, and which get a slider in the menu bar panel.")
        }
    }

    /// Menu of output pairs — check to pin a pair's strip in the mixer, or
    /// to give it a slider in the menu bar panel.
    private var outputsMenu: some View {
        Menu {
            Section("Show in mixer") {
                ForEach(state.physicalOutputGroups, id: \.label) { group in
                    Toggle(isOn: Binding(
                        get: { state.visiblePairLabels.contains(group.label) },
                        set: { _ in state.userToggleOutputPairVisible(label: group.label) }
                    )) {
                        Text(group.label)
                    }
                }
            }
            if !state.menuBarEligibleGroups.isEmpty {
                Section("Show in menu bar") {
                    ForEach(state.menuBarEligibleGroups, id: \.label) { group in
                        Toggle(isOn: Binding(
                            get: { state.menuBarPairLabels.contains(group.label) },
                            set: { _ in state.userToggleMenuBarOutput(label: group.label) }
                        )) {
                            Text(group.label)
                        }
                    }
                }
            }
        } label: {
            // The chevron marks this as a menu rather than an action.
            Pill(icon: "rectangle.split.3x1", title: "Outputs", trailingIcon: "chevron.down")
        }
        // A `.borderlessButton` menu doesn't draw the label's background
        // (`ThemedMenuPicker` relies on that for its flat look); a
        // button-style menu draws the pill as-is.
        .menuStyle(.button)
        .buttonStyle(.pill)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// The copy options for a bus tab, in its dropdown and right-click menu.  A
    /// linked pair copies to other pairs; a mono mix copies to other mono mixes.
    @ViewBuilder
    private func copyMixMenuItems(for bus: MixBus) -> some View {
        let busIdx = bus.matrixIndex ?? 0
        let pair = busIdx / 2
        let pairLabel: (Int) -> String = { "M\($0 * 2 + 1)+M\($0 * 2 + 2)" }
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
        return HStack(alignment: .top, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(stride(from: visibleChannels.lowerBound,
                                         to: visibleChannels.upperBound, by: 2)), id: \.self) { left in
                        channelStrips(startingAt: left)
                    }
                }
                .padding(.vertical, StripLayout.pinnedOutset)
            }
            if state.hasPinnedDawReturn {
                PinnedDawStrip(state: state)
            }
        }
        .padding(10)
        .background { shape.fill(Theme.tabPanel) }
        .overlay { shape.strokeBorder(Theme.tabOutline, lineWidth: 1.5) }
    }
}
