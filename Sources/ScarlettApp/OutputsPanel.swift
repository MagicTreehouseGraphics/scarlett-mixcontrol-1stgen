import SwiftUI
import ScarlettCore

/// The pinned output strips in a panel of their own, with a title that counts
/// how many of the device's output pairs are shown and the button to choose them.
/// Its top and bottom line up with the tab row and the mix panel beside it.
@MainActor
struct OutputsPanel: View {
    @Bindable var state: MixerState
    /// Spare window height below the page, which the panel's plate reaches
    /// down to.  Only the background grows, not the layout: the faders are
    /// sized from the layout's height.
    @Environment(\.pageSpareHeight) private var spare

    private let headerHeight: CGFloat = 24

    var body: some View {
        // The strips set the panel's width.  The header is laid over that
        // width rather than beside it, so a long title can't widen the panel.
        VStack(alignment: .leading, spacing: 12) {
            Color.clear.frame(height: headerHeight)
            PinnedMasterStrip(state: state)
        }
        .frame(minWidth: 210, alignment: .leading)
        .overlay(alignment: .top) { header }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            if AppearanceSettings.shared.look == .analog {
                RaisedFace(shape: RoundedRectangle(cornerRadius: 6), panel: true)
                    .padding(.bottom, -spare)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Theme.tabPanel)
                    .padding(.bottom, -spare)
            }
        }
        .overlay {
            if AppearanceSettings.shared.look == .classic {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.divider, lineWidth: 1)
                    .padding(.bottom, -spare)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("MONITOR & OUTPUTS (\(state.visibleOutputGroups.count)/\(state.physicalOutputGroups.count))")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            outputsMenu
        }
        .frame(height: headerHeight)
    }

    /// Which output pairs are shown as strips here, and which get a slider in
    /// the menu bar panel.  The only place to choose either.
    private var outputsMenu: some View {
        Menu {
            Section("Show in mixer") {
                ForEach(state.physicalOutputGroups, id: \.label) { group in
                    Toggle(isOn: Binding(
                        get: { state.visiblePairLabels.contains(group.label) },
                        set: { _ in state.userToggleOutputPairVisible(label: group.label) }
                    )) {
                        Text(state.outputDisplayName(label: group.label))
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
                            Text(state.outputDisplayName(label: group.label))
                        }
                    }
                }
            }
        } label: {
            Pill(icon: "checklist", title: "Show Outputs")
        }
        // A `.borderlessButton` menu doesn't draw the label's background; a
        // button-style menu draws the pill as-is.
        .menuStyle(.button)
        .buttonStyle(.pill)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose which output pairs are shown as strips here, and which get a slider in the menu bar panel.")
    }
}
