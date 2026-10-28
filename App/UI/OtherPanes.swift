import EventKit
import SwiftUI

struct BatteriesPane: View {
    @EnvironmentObject private var battery: BatteryMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    PaneHeader(title: "Batteries", subtitle: "Ce que le widget affiche en ce moment.")
                    Button("Actualiser") { battery.refresh() }
                }

                VStack(spacing: 0) {
                    ForEach(Array(battery.devices.enumerated()), id: \.element.id) { index, device in
                        if index > 0 { Divider() }
                        HStack(spacing: 12) {
                            Image(systemName: device.kind.symbol).frame(width: 28)
                            Text(device.name)
                            Spacer()
                            if device.isCharging { Image(systemName: "bolt.fill").foregroundStyle(.secondary) }
                            ProgressView(value: Double(device.level), total: 100)
                                .tint(.white)
                                .frame(width: 120)
                            Text("\(device.level) %").monospacedDigit().frame(width: 48, alignment: .trailing)
                        }
                        .padding(.vertical, 10).padding(.horizontal, 14)
                    }
                    if battery.devices.isEmpty {
                        Text("Aucun appareil avec batterie détecté.")
                            .foregroundStyle(.secondary)
                            .padding(14)
                    }
                }
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))

                Text("Pris en charge : batterie du Mac, AirPods et casques Bluetooth, Magic Keyboard, Magic Mouse, Magic Trackpad et manettes. L'iPhone, l'iPad et l'Apple Watch ne partagent leur batterie qu'avec les widgets d'Apple (API privée), ils ne peuvent donc pas apparaître ici.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}

struct CalendarPane: View {
    @EnvironmentObject private var calendar: CalendarSync
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PaneHeader(title: "Calendrier",
                           subtitle: "Les événements des 14 prochains jours sont copiés pour le widget.")

                switch calendar.status {
                case .fullAccess:
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(calendar.calendars, id: \.calendarIdentifier) { cal in
                            Toggle(isOn: Binding(
                                get: { !settings.excludedCalendars.contains(cal.calendarIdentifier) },
                                set: { calendar.setCalendar(cal, included: $0) })) {
                                HStack(spacing: 8) {
                                    Circle().fill(Color(cal.color)).frame(width: 9, height: 9)
                                    Text(cal.title)
                                    Text(cal.source.title).foregroundStyle(.secondary).font(.caption)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(14)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                case .notDetermined:
                    Button("Autoriser l'accès au calendrier") { calendar.requestAccess() }
                        .controlSize(.large)
                default:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("L'accès au calendrier est refusé.")
                        Button("Ouvrir Réglages Système") { calendar.openPrivacySettings() }
                    }
                }
            }
            .padding(24)
        }
    }
}

struct GeneralPane: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.updateMenuBarIcon) private var updateMenuBarIcon

    var body: some View {
        Form {
            Section {
                Toggle("Ouvrir MacWidget à la connexion", isOn: Binding(
                    get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
                Toggle("Masquer l'icône de la barre des menus", isOn: $settings.hideMenuBarIcon)
                    .onChange(of: settings.hideMenuBarIcon) { updateMenuBarIcon() }
            } footer: {
                Text("Icône masquée : rouvre MacWidget depuis le Launchpad ou Spotlight pour revenir ici. L'app doit rester ouverte pour que les batteries, le calendrier et le fond animé se mettent à jour.")
            }
            Section {
                Button("Quitter MacWidget") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
    }
}
