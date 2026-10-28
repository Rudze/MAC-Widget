import SwiftUI

/// Rendu de l'heure, partagé entre le widget et l'aperçu de l'app pour qu'ils soient identiques.
struct ClockFace: View {
    let date: Date
    let appearance: Appearance
    /// Taille de référence des chiffres ; réduite automatiquement si la place manque.
    let size: CGFloat
    var dateSize: CGFloat = 13

    private static let weights: [Font.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]

    static func font(_ appearance: Appearance, size: CGFloat) -> Font {
        let index = Int(appearance.clockWeight.rounded())
        let weight = weights[min(max(index, 0), weights.count - 1)]
        switch appearance.clockFont {
        case .classic: return .system(size: size, weight: weight)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .serif: return .system(size: size, weight: weight, design: .serif)
        case .mono: return .system(size: size, weight: weight, design: .monospaced)
        case .condensed: return .system(size: size, weight: weight).width(.compressed)
        case .expanded: return .system(size: size, weight: weight).width(.expanded)
        case .didot: return .custom("Didot", size: size).weight(weight)
        case .futura: return .custom("Futura", size: size).weight(weight)
        }
    }

    static func color(_ appearance: Appearance) -> Color {
        let c = HexColor.components(appearance.clockColorHex)
        return Color(red: c.red, green: c.green, blue: c.blue).opacity(appearance.clockOpacity)
    }

    private var hour: String { String(format: "%02d", Calendar.current.component(.hour, from: date)) }
    private var minute: String { String(format: "%02d", Calendar.current.component(.minute, from: date)) }

    var body: some View {
        let color = Self.color(appearance)
        VStack(spacing: size * 0.02) {
            if appearance.clockShowDate {
                Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                    .font(.system(size: dateSize, weight: .semibold, design: appearance.clockFont == .rounded ? .rounded : .default))
                    .foregroundStyle(color.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Group {
                if appearance.clockStacked {
                    VStack(spacing: -size * 0.22) {
                        Text(hour)
                        Text(minute)
                    }
                } else {
                    Text("\(hour):\(minute)")
                }
            }
            .font(Self.font(appearance, size: size))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .contentTransition(.numericText())
        }
        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
