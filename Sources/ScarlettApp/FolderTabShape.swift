import SwiftUI

/// A tab with rounded top corners and no bottom edge, like a file-folder tab.
/// Filled, it is a closed block; stroked, only the top and sides are drawn.
struct FolderTabShape: Shape {
    var radius: CGFloat = 6
    /// Pulls the sides and top in, so a stroke centered on the path sits just
    /// inside the bounds, flush with an inside-stroked border next to it.
    var inset: CGFloat = 0
    /// How far the sides run past the bottom edge, to meet a border below.
    var overhang: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let minX = rect.minX + inset, maxX = rect.maxX - inset
        let minY = rect.minY + inset, maxY = rect.maxY + overhang
        let r = min(radius, (maxX - minX) / 2, maxY - minY)
        var path = Path()
        path.move(to: CGPoint(x: minX, y: maxY))
        path.addLine(to: CGPoint(x: minX, y: minY + r))
        path.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX + r, y: minY), radius: r)
        path.addLine(to: CGPoint(x: maxX - r, y: minY))
        path.addArc(tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX, y: minY + r), radius: r)
        path.addLine(to: CGPoint(x: maxX, y: maxY))
        return path
    }
}
