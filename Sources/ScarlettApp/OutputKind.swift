import SwiftUI

/// The icon and colour an output pair stands for, by its label.
struct OutputKind {
    let icon: String
    let color: Color

    init(label: String) {
        let name = label.lowercased()
        if name.contains("monitor") { self.init(icon: "display", color: Theme.textPrimary) }
        else if name.contains("phones") { self.init(icon: "headphones", color: Theme.accentAnalog) }
        else if name.contains("s/pdif") { self.init(icon: "cable.connector", color: Theme.soloActive) }
        else if name.contains("adat") { self.init(icon: "waveform", color: Theme.accentDigital) }
        else { self.init(icon: "hifispeaker.fill", color: Theme.accentInput) }
    }

    private init(icon: String, color: Color) {
        self.icon = icon
        self.color = color
    }
}
