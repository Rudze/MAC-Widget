import SwiftUI
import WidgetKit

struct ClockEntry: TimelineEntry {
    let date: Date
    var appearance = Appearance()
}

struct ClockProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClockEntry { ClockEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (ClockEntry) -> Void) {
        completion(ClockEntry(date: .now, appearance: .current))
    }

    /// Une entrée par minute sur 3 h : aucun réveil de l'extension entre deux minutes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ClockEntry>) -> Void) {
        let appearance = Appearance.current
        let start = Calendar.current.dateInterval(of: .minute, for: .now)?.start ?? .now
        let entries = (0..<180).map {
            ClockEntry(date: start.addingTimeInterval(Double($0) * 60), appearance: appearance)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct ClockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.clock, provider: ClockProvider()) { entry in
            ClockView(entry: entry)
        }
        .configurationDisplayName("Horloge")
        .description("L'heure sans fond, police et couleur réglables dans MacWidget.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct ClockView: View {
    let entry: ClockEntry
    @ResolvedFamily private var family

    var body: some View {
        let (size, dateSize): (CGFloat, CGFloat) = switch family {
        case .systemSmall: (entry.appearance.clockStacked ? 70 : 52, 12)
        case .systemLarge: (entry.appearance.clockStacked ? 170 : 120, 18)
        case .systemExtraLarge: (entry.appearance.clockStacked ? 180 : 230, 22)
        default: (entry.appearance.clockStacked ? 76 : 110, 15)
        }
        ClockFace(date: entry.date, appearance: entry.appearance, size: size, dateSize: dateSize)
            .widgetAccentable()
            .widgetBackground(entry.appearance.clockBackground)
    }
}
