import AppKit
import EventKit
import WidgetKit

/// Copie les prochains événements dans le dossier partagé à chaque changement du calendrier.
@MainActor
final class CalendarSync: ObservableObject {
    @Published private(set) var status = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var calendars: [EKCalendar] = []

    private let store = EKEventStore()
    private let settings = AppSettings.shared
    private var lastEvents: [CalendarEvent]?

    var isAuthorized: Bool { status == .fullAccess }

    func start() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        sync()
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async { self?.sync() }
        }
    }

    func setCalendar(_ calendar: EKCalendar, included: Bool) {
        if included { settings.excludedCalendars.remove(calendar.calendarIdentifier) }
        else { settings.excludedCalendars.insert(calendar.calendarIdentifier) }
        sync()
    }

    func sync() {
        status = EKEventStore.authorizationStatus(for: .event)
        guard isAuthorized else {
            write(authorized: false, events: [])
            return
        }
        calendars = store.calendars(for: .event).sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        let selected = calendars.filter { !settings.excludedCalendars.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else {
            write(authorized: true, events: [])
            return
        }

        let start = Calendar.current.startOfDay(for: Date())
        let end = start.addingTimeInterval(14 * 86_400)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
        let events = store.events(matching: predicate)
            .sorted { a, b in
                let dayA = Calendar.current.startOfDay(for: a.startDate), dayB = Calendar.current.startOfDay(for: b.startDate)
                return (dayA, a.isAllDay ? 0 : 1, a.startDate) < (dayB, b.isAllDay ? 0 : 1, b.startDate)
            }
            .prefix(80)
            .map {
                CalendarEvent(id: "\($0.calendarItemIdentifier)-\($0.startDate.timeIntervalSince1970)",
                              title: $0.title ?? "Sans titre", start: $0.startDate, end: $0.endDate,
                              isAllDay: $0.isAllDay, location: $0.location)
            }
        write(authorized: true, events: Array(events))
    }

    private func write(authorized: Bool, events: [CalendarEvent]) {
        let changed = lastEvents != events || (lastEvents == nil)
        lastEvents = events
        SharedStore.write(CalendarSnapshot(authorized: authorized, events: events, updated: Date()),
                          to: SharedStore.calendarFile)
        if changed { WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.calendar) }
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }
}
