import SwiftUI
import AppKit

/// Popover for giving a mix tab a name and a colour.  Every change is applied
/// as it is made.
struct MixAppearanceEditor: View {
    /// "M3+M4" — which mixes this tab is.
    let title: String
    /// What the tab says with no custom name.
    let placeholder: String
    let onChange: (_ name: String, _ colorHex: String) -> Void

    @State private var name: String
    @State private var colorHex: String
    @FocusState private var nameFocused: Bool

    static let palette: [String] = [
        "#F2594D", "#F5963A", "#F2C94C", "#4DCC66",
        "#2FC4B2", "#4D8CF2", "#9B6BF2", "#F26BB5",
    ]

    init(title: String, placeholder: String, name: String, colorHex: String,
         onChange: @escaping (String, String) -> Void) {
        self.title = title
        self.placeholder = placeholder
        self.onChange = onChange
        _name = State(initialValue: name)
        _colorHex = State(initialValue: colorHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)

            TextField(placeholder, text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit { nameFocused = false }

            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 8) {
                    swatch(hex: "", help: "Default")
                    ForEach(Self.palette, id: \.self) { swatch(hex: $0, help: nil) }
                }
                HueBar(hex: $colorHex)
                    .frame(height: 16)
            }

            HStack {
                Spacer()
                Button("Reset") {
                    name = ""
                    colorHex = ""
                }
                .disabled(name.isEmpty && colorHex.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear { nameFocused = true }
        .onChange(of: name) { onChange(name, colorHex) }
        .onChange(of: colorHex) { onChange(name, colorHex) }
    }

    private func swatch(hex: String, help: String?) -> some View {
        let color = Color(hex: hex)
        let selected = colorHex.uppercased() == hex
        return Button {
            colorHex = hex
        } label: {
            ZStack {
                Circle().fill(color ?? Theme.panelRaised)
                if color == nil {
                    // The default: the app's own blue, shown as an empty ring.
                    Circle().strokeBorder(Theme.tabOutline, lineWidth: 1.5)
                    Image(systemName: "slash.circle")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 20, height: 20)
            .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 0.9 : 0), lineWidth: 2).padding(-3))
        }
        .buttonStyle(.plain)
        .help(help ?? hex)
    }
}

/// A rainbow bar to pick any hue, for colours the swatches don't have.
struct HueBar: View {
    @Binding var hex: String

    private let thumb: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.width - thumb)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(
                        colors: stride(from: 0.0, through: 1.0, by: 1.0 / 6).map { Self.color(hue: $0) },
                        startPoint: .leading, endPoint: .trailing))
                    .frame(height: 8)
                    .padding(.horizontal, thumb / 2)
                if let hue = Self.hue(of: hex) {
                    Circle()
                        .fill(Color(hex: hex) ?? .clear)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                        .frame(width: thumb, height: thumb)
                        .offset(x: CGFloat(hue) * usable)
                }
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let hue = max(0, min(1, Double((drag.location.x - thumb / 2) / usable)))
                    hex = Self.color(hue: hue).hexString ?? hex
                }
            )
        }
        .help("Drag to pick any color")
    }

    private static func color(hue: Double) -> Color {
        Color(hue: hue, saturation: 0.65, brightness: 0.95)
    }

    private static func hue(of hex: String) -> Double? {
        guard let color = Color(hex: hex), let ns = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return Double(ns.hueComponent)
    }
}

/// Popover for naming an output pair and choosing its fader cap colour: the
/// silver default, a swatch, or any hue.  Applied as it is changed.  Outputs
/// without a fader have a name only.
struct OutputAppearanceEditor: View {
    /// The pair's label, shown as the placeholder.
    let label: String
    let showsColor: Bool
    let onChange: (_ name: String, _ colorHex: String) -> Void

    @State private var name: String
    @State private var colorHex: String
    @FocusState private var nameFocused: Bool

    init(label: String, name: String, colorHex: String, showsColor: Bool,
         onChange: @escaping (String, String) -> Void) {
        self.label = label
        self.showsColor = showsColor
        self.onChange = onChange
        _name = State(initialValue: name)
        _colorHex = State(initialValue: colorHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(label, text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit { nameFocused = false }
            if showsColor {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fader color")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 8) {
                        swatch(hex: "")
                        ForEach(MixAppearanceEditor.palette, id: \.self) { swatch(hex: $0) }
                    }
                    HueBar(hex: $colorHex)
                        .frame(height: 16)
                }
            }
            HStack {
                Spacer()
                Button("Reset") {
                    name = ""
                    colorHex = ""
                }
                .disabled(name.isEmpty && colorHex.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear { nameFocused = true }
        .onChange(of: name) { onChange(name, colorHex) }
        .onChange(of: colorHex) { onChange(name, colorHex) }
    }

    private func swatch(hex: String) -> some View {
        let color = Color(hex: hex)
        let selected = colorHex.uppercased() == hex
        return Button {
            colorHex = hex
        } label: {
            Circle()
                .fill(color.map { AnyShapeStyle($0) }
                      ?? AnyShapeStyle(LinearGradient(colors: [Color(white: 0.9), Color(white: 0.55)],
                                                      startPoint: .top, endPoint: .bottom)))
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 0.9 : 0), lineWidth: 2).padding(-3))
        }
        .buttonStyle(.plain)
        .help(color == nil ? "Silver (default)" : hex)
    }
}
