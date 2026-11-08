import SwiftUI
import ScarlettCore

/// The matrix mixer view — Control 2 style.
///
/// Top bar: bus tabs (Mix M1..Mn), grouped in pairs with a link button
/// between the two buses of each.
/// Below: horizontally scrolling row of `ChannelStrip`s, one per matrix
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
            busTabs
            strips
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

    /// The two tabs of one mix pair and the link button between them.  Linked,
    /// the three join into a single wide button that lights up as a whole;
    /// unlinked, they are two separate tabs.
    private func mixPairTabs(_ pair: Int) -> some View {
        let left = state.matrixBuses[pair * 2]
        let right = state.matrixBuses[pair * 2 + 1]
        let linked = state.isMixPairLinked(pair)
        let pairSelected = state.selectedBus == left || state.selectedBus == right
        return HStack(spacing: linked ? 0 : 3) {
            busTab(left, highlighted: linked ? pairSelected : state.selectedBus == left,
                   shape: linked ? .leading : .whole)
            mixLinkButton(pair: pair, linked: linked, highlighted: linked && pairSelected)
            busTab(right, highlighted: linked ? pairSelected : state.selectedBus == right,
                   shape: linked ? .trailing : .whole)
        }
        .padding(.trailing, 8)
    }

    private enum TabShape { case whole, leading, trailing }

    private func busTab(_ bus: MixBus, highlighted: Bool, shape: TabShape) -> some View {
        let radius: CGFloat = 4
        let corners: RectangleCornerRadii = switch shape {
        case .whole: .init(topLeading: radius, bottomLeading: radius, bottomTrailing: radius, topTrailing: radius)
        case .leading: .init(topLeading: radius, bottomLeading: radius, bottomTrailing: 0, topTrailing: 0)
        case .trailing: .init(topLeading: 0, bottomLeading: 0, bottomTrailing: radius, topTrailing: radius)
        }
        return Button {
            state.selectedBus = bus
        } label: {
            Text(bus.displayName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 60, height: 28)
                .background(highlighted ? Theme.muteActive : Theme.panelRaised)
                .foregroundStyle(highlighted ? .white : Theme.textSecondary)
                .clipShape(UnevenRoundedRectangle(cornerRadii: corners))
        }
        .buttonStyle(.plain)
        .contextMenu { copyMixMenuItems(targetBus: bus) }
    }

    private func mixLinkButton(pair: Int, linked: Bool, highlighted: Bool) -> some View {
        let name = "M\(pair * 2 + 1) and M\(pair * 2 + 2)"
        return Button {
            toggleMixLink(pair)
        } label: {
            Image(systemName: "link")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: linked ? 22 : 20, height: linked ? 28 : 22)
                .background(highlighted ? Theme.muteActive : Theme.panelRaised)
                .foregroundStyle(highlighted ? .white : Theme.textSecondary.opacity(linked ? 1 : 0.55))
                .clipShape(RoundedRectangle(cornerRadius: linked ? 0 : 3))
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
        HStack(alignment: .firstTextBaseline) {
            Text("Mixer").font(.title3).bold().foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("Linked mixes (the pair joined by a chain icon) are one stereo mix with pan. Click the link to split them into two mono mixes. Use the strips' source pickers to wire signals in.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 380)
        }
    }

    private var busTabs: some View {
        HStack(spacing: 4) {
            ForEach(0..<state.stereoPairCount, id: \.self) { pair in
                mixPairTabs(pair)
            }
            Spacer()
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

    /// Context-menu items for a bus tab — copy this pair's settings to
    /// another pair.  Right-click any bus tab to access.
    @ViewBuilder
    private func copyMixMenuItems(targetBus: MixBus) -> some View {
        let sourcePair = targetBus.stereoPairIndex ?? 0
        let pairLabel: (Int) -> String = { p in "M\(p*2 + 1)+M\(p*2 + 2)" }
        ForEach(0..<state.stereoPairCount, id: \.self) { dest in
            if dest != sourcePair {
                Button("Copy \(pairLabel(sourcePair)) → \(pairLabel(dest))") {
                    state.userCopyMixPair(from: sourcePair, to: dest)
                }
            }
        }
    }

    private var strips: some View {
        HStack(alignment: .top, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(visibleChannels, id: \.self) { ch in
                        ChannelStrip(channel: ch, state: state)
                    }
                }
                .padding(.vertical, StripLayout.pinnedOutset)
            }
            if state.hasPinnedDawReturn {
                PinnedDawStrip(state: state)
            }
            PinnedMasterStrip(state: state)
        }
    }
}
