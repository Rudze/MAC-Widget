import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case widgets, floating, appearance, photos, wallpaper, batteries, calendar, github, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .widgets: "Widgets"
        case .floating: "Widgets flottants"
        case .appearance: "Apparence"
        case .photos: "Cadres photo"
        case .wallpaper: "Fond d'écran"
        case .batteries: "Batteries"
        case .calendar: "Calendrier"
        case .github: "GitHub"
        case .general: "Général"
        }
    }

    var symbol: String {
        switch self {
        case .widgets: "square.grid.2x2"
        case .floating: "macwindow.on.rectangle"
        case .appearance: "paintbrush"
        case .photos: "photo.on.rectangle"
        case .wallpaper: "play.rectangle"
        case .batteries: "battery.75percent"
        case .calendar: "calendar"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .general: "gearshape"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var navigation: Navigation

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $navigation.section) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch navigation.section {
                case .widgets: WidgetsPane()
                case .floating: FloatingPane()
                case .appearance: AppearancePane()
                case .photos: PhotosPane()
                case .wallpaper: WallpaperPane()
                case .batteries: BatteriesPane()
                case .calendar: CalendarPane()
                case .github: GitHubPane()
                case .general: GeneralPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(navigation.section.title)
        }
    }
}

/// En-tête commun des panneaux.
struct PaneHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WidgetsPane: View {
    private let widgets: [(String, String, String)] = [
        ("clock", "Horloge", "L'heure sans fond, police et couleur au choix."),
        ("cpu", "Ressources", "Processeur, mémoire, stockage et batterie."),
        ("chevron.left.forwardslash.chevron.right", "GitHub", "Graphe de contributions et derniers commits."),
        ("music.note", "Musique", "Morceau en cours dans Apple Music, lecture / pause / suivant."),
        ("battery.75percent", "Batteries", "Mac, écouteurs, clavier, souris… anneaux blancs."),
        ("calendar", "Calendrier", "Date du jour, mois et prochains événements."),
        ("photo", "Cadre photo 1, 2 et 3", "Tes photos, cadrées au millimètre, en diaporama si tu veux."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaneHeader(title: "Tes widgets",
                           subtitle: "Ils s'ajoutent comme les widgets d'Apple, directement sur le bureau.")

                VStack(alignment: .leading, spacing: 10) {
                    Label("Clic droit sur le bureau → **Modifier les widgets…**", systemImage: "1.circle.fill")
                    Label("Cherche **MacWidget** dans la liste de gauche", systemImage: "2.circle.fill")
                    Label("Glisse le widget voulu sur le bureau (ou dans le Centre de notifications)", systemImage: "3.circle.fill")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    ForEach(widgets, id: \.1) { symbol, title, text in
                        HStack(spacing: 14) {
                            Image(systemName: symbol)
                                .font(.system(size: 22, weight: .light))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.06)],
                                                           startPoint: .top, endPoint: .bottom),
                                            in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title).font(.headline)
                                Text(text).font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                    }
                }

                Label {
                    Text("Astuce : pour garder les widgets blancs et les photos en couleur même quand une fenêtre est au premier plan, va dans **Réglages Système → Bureau et Dock → Style des widgets → Couleur**.")
                } icon: {
                    Image(systemName: "lightbulb")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}
