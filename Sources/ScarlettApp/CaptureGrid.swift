import SwiftUI
import ScarlettCore

/// The USB capture tab: every capture channel as a small cell in a grid, grouped
/// by the kind of input it carries from the factory (Analog, S/PDIF, ADAT).
/// Each channel is routed on its own, since the inputs are usually unrelated.
@MainActor
struct CaptureGrid: View {
    @Bindable var state: MixerState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(state.captureChannelGroups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.leading, 2)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 8)],
                              alignment: .leading, spacing: 8) {
                        ForEach(group.channels, id: \.self) { CaptureCell(state: state, channel: $0) }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One USB capture channel: a slim meter, its number, and what feeds it.
@MainActor
private struct CaptureCell: View {
    @Bindable var state: MixerState
    let channel: Int

    private let meterHeight: CGFloat = 52

    var body: some View {
        let bus = state.captureRoutes[channel] ?? .off
        HStack(alignment: .center, spacing: 10) {
            RoutedMeter(state: state, source: bus, profile: state.profile)
                .environment(\.faderHeight, meterHeight)
                .frame(width: 14, height: meterHeight)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("DAW in \(channel + 1)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if !state.isCaptureChannelAtFactory(channel) {
                        Circle()
                            .fill(Theme.muteActive)
                            .frame(width: 5, height: 5)
                            .help("Differs from the factory setup (\(state.factoryCaptureName(channel: channel) ?? "its own input")).")
                            .accessibilityLabel("Differs from the factory setup")
                    }
                }
                picker(bus)
                Rectangle()
                    .fill(state.routeColor(bus) ?? Theme.textSecondary.opacity(0.5))
                    .frame(height: 2)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stripCard()
    }

    private func picker(_ bus: MixBus) -> some View {
        let binding = Binding(get: { bus }, set: { state.userSetCaptureRoute(channel: channel, to: $0) })
        return Menu {
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
