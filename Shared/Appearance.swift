import Foundation

enum WidgetBackground: String, Codable, CaseIterable, Identifiable {
    /// Transparent : seulement possible pour les widgets flottants. Dans la galerie, macOS met du noir.
    case none, black, graphite, custom

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        self = WidgetBackground(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .black
    }

    var label: String {
        switch self {
        case .none: "Aucun"
        case .black: "Noir"
        case .graphite: "Graphite"
        case .custom: "Couleur"
        }
    }
}

struct WidgetStyle: Codable, Hashable {
    var background: WidgetBackground
    var customHex = "#1C1C1E"
    var opacity = 1.0

    init(background: WidgetBackground) { self.background = background }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        background = try c.decodeIfPresent(WidgetBackground.self, forKey: .background) ?? .black
        customHex = try c.decodeIfPresent(String.self, forKey: .customHex) ?? "#1C1C1E"
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
    }
}

/// Polices proposées pour l'heure, à la manière de l'écran verrouillé de l'iPhone.
enum ClockFont: String, Codable, CaseIterable, Identifiable {
    case classic, rounded, serif, mono, condensed, expanded, didot, futura

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: "Classique"
        case .rounded: "Arrondie"
        case .serif: "Serif"
        case .mono: "Mono"
        case .condensed: "Étroite"
        case .expanded: "Large"
        case .didot: "Didot"
        case .futura: "Futura"
        }
    }
}

/// Apparence des widgets, réglée dans l'app et lue par l'extension.
struct Appearance: Codable, Hashable {
    var clockFont = ClockFont.classic
    /// 0 (ultra fin) à 8 (noir), comme le curseur d'épaisseur de l'iPhone.
    var clockWeight = 5.0
    var clockColorHex = "#FFFFFF"
    var clockOpacity = 1.0
    var clockStacked = false
    var clockShowDate = true
    var clockBackground = WidgetStyle(background: .black)
    var calendar = WidgetStyle(background: .black)
    var battery = WidgetStyle(background: .graphite)
    var github = WidgetStyle(background: .black)
    var system = WidgetStyle(background: .graphite)
    var music = WidgetStyle(background: .black)

    static let file = "appearance.json"
    static var current: Appearance { SharedStore.read(Appearance.self, from: file) ?? Appearance() }

    init() {}

    // Tolère les clés absentes pour qu'un ancien fichier reste lisible après une mise à jour.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Appearance()
        clockFont = (try? c.decodeIfPresent(ClockFont.self, forKey: .clockFont)) ?? d.clockFont
        clockWeight = try c.decodeIfPresent(Double.self, forKey: .clockWeight) ?? d.clockWeight
        clockColorHex = try c.decodeIfPresent(String.self, forKey: .clockColorHex) ?? d.clockColorHex
        clockOpacity = try c.decodeIfPresent(Double.self, forKey: .clockOpacity) ?? d.clockOpacity
        clockStacked = try c.decodeIfPresent(Bool.self, forKey: .clockStacked) ?? d.clockStacked
        clockShowDate = try c.decodeIfPresent(Bool.self, forKey: .clockShowDate) ?? d.clockShowDate
        clockBackground = try c.decodeIfPresent(WidgetStyle.self, forKey: .clockBackground) ?? d.clockBackground
        calendar = try c.decodeIfPresent(WidgetStyle.self, forKey: .calendar) ?? d.calendar
        battery = try c.decodeIfPresent(WidgetStyle.self, forKey: .battery) ?? d.battery
        github = try c.decodeIfPresent(WidgetStyle.self, forKey: .github) ?? d.github
        system = try c.decodeIfPresent(WidgetStyle.self, forKey: .system) ?? d.system
        music = try c.decodeIfPresent(WidgetStyle.self, forKey: .music) ?? d.music
    }
}

/// "#RRGGBB" ↔ composantes 0…1.
enum HexColor {
    static func components(_ hex: String) -> (red: Double, green: Double, blue: Double) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    static func string(red: Double, green: Double, blue: Double) -> String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}
