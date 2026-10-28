import SwiftUI
import WidgetKit

struct CalendarEntry: TimelineEntry {
    let date: Date
    let authorized: Bool
    let events: [CalendarEvent]
    var style = Appearance().calendar
}

struct CalendarProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarEntry {
        let now = Date()
        return CalendarEntry(date: now, authorized: true, events: [
            CalendarEvent(id: "1", title: "Réunion d'équipe", start: now.addingTimeInterval(3600),
                          end: now.addingTimeInterval(7200), isAllDay: false, location: nil),
            CalendarEvent(id: "2", title: "Sport", start: now.addingTimeInterval(4 * 3600),
                          end: now.addingTimeInterval(5 * 3600), isAllDay: false, location: nil),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarEntry) -> Void) {
        guard let s = snapshot(), s.authorized || !context.isPreview else {
            completion(placeholder(in: context)); return
        }
        completion(entry(at: .now, s, Appearance.current.calendar))
    }

    /// Une entrée à chaque début/fin d'événement et à minuit, pour que
    /// « prochain événement » reste juste sans réveiller l'app.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarEntry>) -> Void) {
        let now = Date()
        let s = snapshot() ?? CalendarSnapshot(authorized: false, events: [], updated: now)
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: now.addingTimeInterval(86_400))
        var points = Set<Date>([now, midnight])
        for e in s.events where !e.isAllDay {
            if e.start > now && e.start < midnight { points.insert(e.start) }
            if e.end > now && e.end < midnight { points.insert(e.end) }
        }
        let style = Appearance.current.calendar
        let entries = points.sorted().prefix(40).map { entry(at: $0, s, style) }
        completion(Timeline(entries: Array(entries), policy: .after(midnight.addingTimeInterval(5))))
    }

    private func snapshot() -> CalendarSnapshot? {
        SharedStore.read(CalendarSnapshot.self, from: SharedStore.calendarFile)
    }

    private func entry(at date: Date, _ s: CalendarSnapshot, _ style: WidgetStyle) -> CalendarEntry {
        CalendarEntry(date: date, authorized: s.authorized, events: s.events.filter { $0.end > date }, style: style)
    }
}

struct CalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.calendar, provider: CalendarProvider()) { entry in
            CalendarView(entry: entry)
        }
        .configurationDisplayName("Calendrier")
        .description("La date du jour et tes prochains événements, en blanc.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CalendarView: View {
    let entry: CalendarEntry
    @ResolvedFamily private var family

    private var cal: Calendar { .current }
    private var day: String { "\(cal.component(.day, from: entry.date))" }
    private var weekday: String { entry.date.formatted(.dateTime.weekday(.wide)).uppercased() }
    private var month: String { entry.date.formatted(.dateTime.month(.wide)).capitalized }

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            case .systemLarge: large
            default: medium
            }
        }
        .foregroundStyle(Theme.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetBackground(entry.style)
        .widgetURL(WidgetLink.calendar.url)
    }

    // MARK: Tailles

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(weekday)
                .font(.system(size: 11, weight: .bold)).tracking(1)
                .foregroundStyle(Theme.secondary)
            Text(day)
                .font(.system(size: 46, weight: .light))
                .padding(.top, -4)
                .widgetAccentable()
            Spacer(minLength: 4)
            eventsList(limit: 1, compact: true)
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                Text(weekday)
                    .font(.system(size: 11, weight: .bold)).tracking(1)
                    .foregroundStyle(Theme.secondary)
                Text(day)
                    .font(.system(size: 58, weight: .light))
                    .padding(.top, -6)
                    .widgetAccentable()
                Spacer(minLength: 0)
                Text(month)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }
            .frame(width: 92, alignment: .leading)
            eventsList(limit: 3, compact: false)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(month).font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(entry.date.formatted(.dateTime.year()))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }
            MonthGrid(date: entry.date)
            Divider().overlay(Theme.track)
            eventsList(limit: 3, compact: false)
        }
    }

    // MARK: Événements

    @ViewBuilder
    private func eventsList(limit: Int, compact: Bool) -> some View {
        if !entry.authorized {
            Label("Ouvre MacWidget pour autoriser le calendrier", systemImage: "lock")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
        } else if entry.events.isEmpty {
            Text("Rien de prévu")
                .font(.system(size: compact ? 12 : 13, weight: .medium))
                .foregroundStyle(Theme.secondary)
        } else {
            VStack(alignment: .leading, spacing: compact ? 4 : 9) {
                ForEach(entry.events.prefix(limit)) { e in
                    EventRow(event: e, now: entry.date, compact: compact)
                }
                let rest = entry.events.count - limit
                if rest > 0 && !compact {
                    Text("+ \(rest) autre\(rest > 1 ? "s" : "")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.tertiary)
                }
            }
        }
    }
}

struct EventRow: View {
    let event: CalendarEvent
    let now: Date
    let compact: Bool

    private var isNow: Bool { !event.isAllDay && event.start <= now && event.end > now }

    private var timeText: String {
        let cal = Calendar.current
        var prefix = ""
        if !cal.isDate(event.start, inSameDayAs: now) && event.start > now {
            prefix = cal.isDateInTomorrow(event.start)
                ? "Demain · "
                : event.start.formatted(.dateTime.weekday(.abbreviated).day()) + " · "
        }
        if event.isAllDay { return prefix + "Toute la journée" }
        if isNow { return "En cours · jusqu'à \(event.end.hm)" }
        return prefix + "\(event.start.hm) – \(event.end.hm)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isNow ? Theme.primary : Theme.secondary)
                .frame(width: 3)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .lineLimit(compact ? 2 : 1)
                Text(timeText)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct MonthGrid: View {
    let date: Date

    private var cal: Calendar { .current }

    private var symbols: [String] {
        let s = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(s[first...] + s[..<first])
    }

    private var cells: [Int?] {
        guard let interval = cal.dateInterval(of: .month, for: date),
              let range = cal.range(of: .day, in: .month, for: date) else { return [] }
        let weekday = cal.component(.weekday, from: interval.start)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        var result: [Int?] = Array(repeating: nil, count: leading) + range.map { Optional($0) }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    var body: some View {
        let today = cal.component(.day, from: date)
        let rows = cells.count / 7
        Grid(horizontalSpacing: 0, verticalSpacing: 3) {
            GridRow {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, s in
                    Text(s.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<rows, id: \.self) { r in
                GridRow {
                    ForEach(0..<7, id: \.self) { c in
                        let value = cells[r * 7 + c]
                        Text(value.map(String.init) ?? "")
                            .font(.system(size: 12, weight: value == today ? .bold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(value == today ? Color.black : Theme.primary.opacity(0.85))
                            .frame(width: 22, height: 22)
                            .background {
                                if value == today { Circle().fill(Theme.primary).widgetAccentable() }
                            }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}
