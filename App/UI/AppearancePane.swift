import SwiftUI
import WidgetKit

/// Enregistre l'apparence et recharge les widgets concernés (regroupé pendant un glissement de curseur).
@MainActor
final class AppearanceStore: ObservableObject {
    @Published var value: Appearance {
        didSet { if value != oldValue { scheduleSave() } }
    }

    private var pending: DispatchWorkItem?

    init() { value = .current }

    private func scheduleSave() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            SharedStore.write(self.value, to: Appearance.file)
            for kind in [WidgetKinds.clock, WidgetKinds.calendar, WidgetKinds.battery, WidgetKinds.github,
                         WidgetKinds.system, WidgetKinds.music] {
                WidgetCenter.shared.reloadTimelines(ofKind: kind)
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}

struct AppearancePane: View {
    @EnvironmentObject private var store: AppearanceStore
    @EnvironmentObject private var floating: FloatingWidgets

    var body: some View {
        Form {
            Section {
                ClockEditor(appearance: $store.value)
            } header: {
                Label("Horloge", systemImage: "clock")
            }
            Section {
                StyleEditor(style: $store.value.clockBackground)
            } header: {
                Label("Fond de l'horloge", systemImage: "square.dashed")
            }
            Section {
                StyleEditor(style: $store.value.calendar)
            } header: {
                Label("Calendrier", systemImage: "calendar")
            }
            Section {
                StyleEditor(style: $store.value.battery)
            } header: {
                Label("Batteries", systemImage: "battery.75percent")
            }
            Section {
                StyleEditor(style: $store.value.system)
            } header: {
                Label("Ressources", systemImage: "cpu")
            }
            Section {
                StyleEditor(style: $store.value.music)
            } header: {
                Label("Musique", systemImage: "music.note")
            }
            Section {
                StyleEditor(style: $store.value.github)
            } header: {
                Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            } footer: {
                Text(floating.isEnabled
                     ? "« Aucun » et l'opacité ne s'appliquent qu'aux widgets flottants : dans la galerie, macOS impose toujours un fond (noir si « Aucun »)."
                     : "macOS impose toujours un fond aux widgets de la galerie. Pour un fond transparent, active les widgets flottants ; pour du verre dépoli, Réglages Système → Bureau et Dock → Style des widgets → Monochrome.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Horloge façon écran verrouillé

private struct ClockEditor: View {
    @Binding var appearance: Appearance

    private let swatches = ["#FFFFFF", "#F5E6C8", "#FFD6E0", "#CDE7FF", "#C9F2DD", "#E3D4FF", "#FFE08A", "#9AA0A6"]

    private var color: Binding<Color> {
        Binding(
            get: {
                let c = HexColor.components(appearance.clockColorHex)
                return Color(red: c.red, green: c.green, blue: c.blue)
            },
            set: { newValue in
                let ns = NSColor(newValue).usingColorSpace(.sRGB) ?? .white
                appearance.clockColorHex = HexColor.string(red: Double(ns.redComponent),
                                                           green: Double(ns.greenComponent),
                                                           blue: Double(ns.blueComponent))
            })
    }

    var body: some View {
        // Aperçu sur un dégradé façon fond d'écran : l'horloge du bureau n'a pas de fond.
        TimelineView(.everyMinute) { context in
            ClockFace(date: context.date, appearance: appearance, size: appearance.clockStacked ? 96 : 84, dateSize: 15)
                .frame(height: appearance.clockStacked ? 230 : 160)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [Color(red: 0.16, green: 0.2, blue: 0.3), Color(red: 0.05, green: 0.06, blue: 0.1)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14)
                )
        }

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(ClockFont.allCases) { font in
                let selected = appearance.clockFont == font
                Button {
                    appearance.clockFont = font
                } label: {
                    VStack(spacing: 2) {
                        Text("12")
                            .font(ClockFace.font({ var a = appearance; a.clockFont = font; return a }(), size: 30))
                        Text(font.label).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }

        HStack {
            Text("Épaisseur")
            Image(systemName: "textformat.size.smaller").foregroundStyle(.secondary)
            Slider(value: $appearance.clockWeight, in: 0...8, step: 1)
            Image(systemName: "textformat.size.larger").foregroundStyle(.secondary)
        }

        HStack(spacing: 10) {
            Text("Couleur")
            Spacer()
            ForEach(swatches, id: \.self) { hex in
                let c = HexColor.components(hex)
                Circle()
                    .fill(Color(red: c.red, green: c.green, blue: c.blue))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(Color.accentColor,
                                                   lineWidth: appearance.clockColorHex == hex ? 2 : 0).padding(-3))
                    .onTapGesture { appearance.clockColorHex = hex }
            }
            ColorPicker("", selection: color, supportsOpacity: false).labelsHidden()
        }

        HStack {
            Text("Opacité")
            Slider(value: $appearance.clockOpacity, in: 0.2...1)
            Text("\(Int(appearance.clockOpacity * 100)) %")
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
        }

        Picker("Disposition", selection: $appearance.clockStacked) {
            Text("21:07").tag(false)
            Text("21 / 07 superposés").tag(true)
        }
        .pickerStyle(.segmented)

        Toggle("Afficher la date au-dessus", isOn: $appearance.clockShowDate)
    }
}

// MARK: - Fond des autres widgets

private struct StyleEditor: View {
    @Binding var style: WidgetStyle
    @EnvironmentObject private var floating: FloatingWidgets

    /// « Aucun » n'a de sens que pour les widgets flottants.
    private var choices: [WidgetBackground] {
        floating.isEnabled || style.background == .none
            ? WidgetBackground.allCases : WidgetBackground.allCases.filter { $0 != .none }
    }

    private var color: Binding<Color> {
        Binding(
            get: {
                let c = HexColor.components(style.customHex)
                return Color(red: c.red, green: c.green, blue: c.blue)
            },
            set: { newValue in
                let ns = NSColor(newValue).usingColorSpace(.sRGB) ?? .black
                style.customHex = HexColor.string(red: Double(ns.redComponent),
                                                  green: Double(ns.greenComponent),
                                                  blue: Double(ns.blueComponent))
            })
    }

    var body: some View {
        Picker("Fond", selection: $style.background) {
            ForEach(choices) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)

        if style.background == .custom {
            ColorPicker("Couleur du fond", selection: color, supportsOpacity: false)
        }
        if floating.isEnabled && style.background != .none {
            HStack {
                Text("Opacité")
                Slider(value: $style.opacity, in: 0.2...1)
                Text("\(Int(style.opacity * 100)) %")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}
