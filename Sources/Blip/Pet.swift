import AppKit
import SwiftUI

/// Humeur du compagnon selon le nombre de notifications non lues.
enum Mood: CaseIterable {
    case zen, happy, worried, panic

    init(unread: Int) {
        switch unread {
        case 0: self = .zen
        case ...4: self = .happy
        case ...14: self = .worried
        default: self = .panic
        }
    }
}

/// Sprite 16×16 en pixel art. Chaque caractère est un pixel :
/// `#` corps, `e`/`m`/`b` yeux, bouche, sourcils, `w` blanc, `c` joues, `s` sueur, `x` alerte,
/// et les accessoires (`g` pousse, `p`/`q` casquette, `k`/`r` couronne). `.` est transparent.
enum Pet {
    static let size = 16

    struct Accessory: Sendable {
        let level: Int
        let name: String
        fileprivate let layer: Layer
    }

    /// Ligne → pixels superposés ; un espace laisse le pixel du dessous.
    fileprivate typealias Layer = [Int: String]

    static let accessories = [
        Accessory(level: 5, name: "une pousse", layer: [
            0: "        gg      ",
            1: "       gg       ",
            2: "       g        ",
        ]),
        Accessory(level: 10, name: "une casquette", layer: [
            0: "      pppp      ",
            1: "     pppppp     ",
            2: "     ppppppqq   ",
        ]),
        Accessory(level: 20, name: "une couronne", layer: [
            0: "     k kk k     ",
            1: "     kkkkkk     ",
            2: "     kkrrkk     ",
        ]),
    ]

    static func accessory(for level: Int) -> Accessory? {
        accessories.last { level >= $0.level }
    }

    private static let body = [
        "................",
        "................",
        "................",
        ".....######.....",
        "...##########...",
        "..############..",
        ".##############.",
        ".##############.",
        ".##############.",
        ".##############.",
        ".##############.",
        ".##############.",
        ".##############.",
        "..############..",
        "...###....###...",
        "................",
    ]

    private static let openEyes: Layer = [7: "    we    we    ", 8: "    ee    ee    "]
    private static let closedEyes: Layer = [8: "    ee    ee    "]
    private static let smile: Layer = [9: "   c        c   ", 10: "      m  m      ", 11: "       mm       "]
    private static let sweat: Layer = [2: "  s             ", 3: " ss             ", 4: " ss             "]
    private static let alert: Layer = [0: "              xx", 1: "              xx", 2: "              xx", 4: "              xx"]

    private static func face(_ mood: Mood, blink: Bool) -> [Layer] {
        let eyes = blink ? closedEyes : openEyes
        return switch mood {
        case .zen: [[7: "     e    e     ", 8: "    e e  e e    "], smile]
        case .happy: [eyes, smile]
        case .worried: [eyes, sweat, [4: "     b    b     ", 5: "    b      b    ", 11: "      mmmm      "]]
        case .panic: [sweat, [
            6: "   www    www   ", 7: "   wew    wew   ", 8: "   www    www   ",
            10: "      mmmm      ", 11: "      mmmm      ", 12: "       mm       ",
        ]]
        }
    }

    static func grid(mood: Mood, level: Int, alert: Bool, blink: Bool = false) -> [[Character]] {
        var grid = body.map(Array.init)
        var layers = face(mood, blink: blink)
        if let accessory = accessory(for: level) { layers.append(accessory.layer) }
        if alert { layers.append(Self.alert) }
        for layer in layers {
            for (row, pixels) in layer {
                for (column, pixel) in pixels.enumerated() where pixel != " " {
                    grid[row][column] = pixel
                }
            }
        }
        return grid
    }

    // MARK: - Rendu couleur

    private static let palette: [Character: UInt32] = [
        "e": 0x2A2438, "m": 0x2A2438, "b": 0x2A2438, "w": 0xFFFFFF, "c": 0xFF9FB2,
        "s": 0x5AB8FF, "x": 0xFF453A, "g": 0x4CC46A, "p": 0x6C63FF, "q": 0x4B44C9,
        "k": 0xFFC93C, "r": 0xE5484D,
    ]

    static func bodyColor(_ mood: Mood) -> (fill: UInt32, edge: UInt32) {
        switch mood {
        case .zen: (0x8FD3FF, 0x3E8EC4)
        case .happy: (0x7EE2A8, 0x2F9E66)
        case .worried: (0xFFD166, 0xC9962B)
        case .panic: (0xFF8A80, 0xD14B42)
        }
    }

    /// Pixels colorés ; le corps reçoit un contour plus sombre là où il touche le vide.
    static func coloredPixels(mood: Mood, level: Int, alert: Bool, blink: Bool = false) -> [(x: Int, y: Int, rgb: UInt32)] {
        let grid = grid(mood: mood, level: level, alert: alert, blink: blink)
        let colors = bodyColor(mood)
        func isVoid(_ x: Int, _ y: Int) -> Bool {
            !(0..<size).contains(x) || !(0..<size).contains(y) || grid[y][x] == "."
        }
        var pixels: [(x: Int, y: Int, rgb: UInt32)] = []
        for y in 0..<size {
            for x in 0..<size {
                let pixel = grid[y][x]
                if pixel == "#" {
                    let edge = isVoid(x - 1, y) || isVoid(x + 1, y) || isVoid(x, y - 1) || isVoid(x, y + 1)
                    pixels.append((x, y, edge ? colors.edge : colors.fill))
                } else if let rgb = palette[pixel] {
                    pixels.append((x, y, rgb))
                }
            }
        }
        return pixels
    }

    // MARK: - Barre de menus

    /// Hauteur réservée au-dessus et au-dessous du sprite pour qu'il puisse sauter sans changer de taille.
    static let maxLift = 3

    /// Par défaut une image « template » monochrome (yeux et bouche en creux) que macOS adapte
    /// au thème ; en couleur quand il y a du nouveau. `lift` soulève le sprite pour l'animation.
    static func menuBarImage(mood: Mood, level: Int, alert: Bool, colored: Bool = false, lift: Int = 0) -> NSImage {
        let dots = colored
            ? coloredPixels(mood: mood, level: level, alert: alert)
            : grid(mood: mood, level: level, alert: alert).enumerated().flatMap { y, row in
                row.enumerated().compactMap { x, pixel in isOpaqueInTemplate(pixel) ? (x: x, y: y, rgb: UInt32(0)) : nil }
            }
        let top = dots.map(\.y).min() ?? 0
        let height = (dots.map(\.y).max() ?? size - 1) - top + 1 + 2 * maxLift
        let offset = maxLift - lift - top
        let image = NSImage(size: NSSize(width: size, height: height), flipped: true) { _ in
            NSGraphicsContext.current?.shouldAntialias = false
            for dot in dots {
                NSColor(rgb: dot.rgb).setFill()
                NSRect(x: dot.x, y: dot.y + offset, width: 1, height: 1).fill()
            }
            return true
        }
        image.isTemplate = !colored
        return image
    }

    private static func isOpaqueInTemplate(_ pixel: Character) -> Bool {
        !".embw".contains(pixel)
    }
}

struct PetView: View {
    let mood: Mood
    let level: Int
    var alert = false
    var blink = false

    var body: some View {
        Canvas { context, size in
            let pixel = min(size.width, size.height) / CGFloat(Pet.size)
            for dot in Pet.coloredPixels(mood: mood, level: level, alert: alert, blink: blink) {
                let rect = CGRect(x: CGFloat(dot.x) * pixel, y: CGFloat(dot.y) * pixel, width: pixel, height: pixel)
                context.fill(Path(rect), with: .color(Color(rgb: dot.rgb)), style: FillStyle(antialiased: false))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
