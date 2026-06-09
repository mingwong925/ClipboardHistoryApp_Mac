import AppKit

extension NSColor {
    var isDark: Bool {
        guard let color = usingColorSpace(.deviceRGB) else { return false }
        let red = color.redComponent
        let green = color.greenComponent
        let blue = color.blueComponent
        // Perceived luminance formula
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        return luminance < 0.5
    }
}
