import SwiftUI
import WidgetKit

// MARK: - Style commun (widgets de la galerie et widgets flottants)

enum Theme {
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.58)
    static let tertiary = Color.white.opacity(0.32)
    static let track = Color.white.opacity(0.16)

    @ViewBuilder
    static func background(_ style: WidgetStyle) -> some View {
        switch style.background {
        case .none:
            Color.clear
        case .black:
            Color.black.opacity(style.opacity)
        case .graphite:
            LinearGradient(colors: [Color(white: 0.17), Color(white: 0.06)], startPoint: .top, endPoint: .bottom)
                .opacity(style.opacity)
        case .custom:
            let c = HexColor.components(style.customHex)
            Color(red: c.red, green: c.green, blue: c.blue).opacity(style.opacity)
        }
    }
}

/// Taille imposée quand la vue est affichée en widget flottant, hors de WidgetKit
/// (`widgetFamily` y est en lecture seule).
private struct FloatingFamilyKey: EnvironmentKey {
    static let defaultValue: WidgetFamily? = nil
}

extension EnvironmentValues {
    var floatingFamily: WidgetFamily? {
        get { self[FloatingFamilyKey.self] }
        set { self[FloatingFamilyKey.self] = newValue }
    }
}

/// Taille effective : celle du widget flottant, sinon celle donnée par WidgetKit.
@propertyWrapper
struct ResolvedFamily: DynamicProperty {
    @Environment(\.widgetFamily) private var system
    @Environment(\.floatingFamily) private var floating
    var wrappedValue: WidgetFamily { floating ?? system }
}

private struct WidgetBackgroundModifier: ViewModifier {
    let style: WidgetStyle
    @Environment(\.floatingFamily) private var floating

    func body(content: Content) -> some View {
        Group {
            if floating != nil {
                // Fenêtre transparente : on dessine le fond nous-mêmes, « Aucun » est vraiment transparent.
                content
                    .shadow(color: .black.opacity(style.background == .none ? 0.45 : 0), radius: 3, y: 1)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background(style).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)))
            } else {
                // Galerie : macOS impose un fond (noir si « Aucun »).
                content.containerBackground(for: .widget) { Theme.background(style) }
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

extension View {
    func widgetBackground(_ style: WidgetStyle) -> some View {
        modifier(WidgetBackgroundModifier(style: style))
    }
}

extension Image {
    /// Garde la photo en couleur quand le bureau passe les widgets en mode teinté.
    @ViewBuilder
    func fullColorResizable() -> some View {
        if #available(macOS 15.0, *) {
            self.resizable().widgetAccentedRenderingMode(.fullColor)
        } else {
            self.resizable()
        }
    }
}

extension Date {
    var frLongDate: String { formatted(.dateTime.weekday(.wide).day().month(.wide)) }
    var hm: String { formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
}
