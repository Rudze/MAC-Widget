import Foundation
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var wallpaperEnabled: Bool { didSet { d.set(wallpaperEnabled, forKey: "wallpaperEnabled") } }
    @Published var wallpaperPath: String? { didSet { d.set(wallpaperPath, forKey: "wallpaperPath") } }
    @Published var pauseOnBattery: Bool { didSet { d.set(pauseOnBattery, forKey: "pauseOnBattery") } }
    @Published var pauseInLowPower: Bool { didSet { d.set(pauseInLowPower, forKey: "pauseInLowPower") } }
    @Published var syncSystemWallpaper: Bool { didSet { d.set(syncSystemWallpaper, forKey: "syncSystemWallpaper") } }
    @Published var hideMenuBarIcon: Bool { didSet { d.set(hideMenuBarIcon, forKey: "hideMenuBarIcon") } }
    @Published var excludedCalendars: Set<String> {
        didSet { d.set(Array(excludedCalendars), forKey: "excludedCalendars") }
    }

    var didOnboard: Bool {
        get { d.bool(forKey: "didOnboard") }
        set { d.set(newValue, forKey: "didOnboard") }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            if newValue { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        }
    }

    private init() {
        d.register(defaults: [
            "pauseOnBattery": false,
            "pauseInLowPower": true,
            "syncSystemWallpaper": true,
        ])
        wallpaperEnabled = d.bool(forKey: "wallpaperEnabled")
        wallpaperPath = d.string(forKey: "wallpaperPath")
        pauseOnBattery = d.bool(forKey: "pauseOnBattery")
        pauseInLowPower = d.bool(forKey: "pauseInLowPower")
        syncSystemWallpaper = d.bool(forKey: "syncSystemWallpaper")
        hideMenuBarIcon = d.bool(forKey: "hideMenuBarIcon")
        excludedCalendars = Set(d.stringArray(forKey: "excludedCalendars") ?? [])
    }
}

extension Notification.Name {
    static let powerSourceChanged = Notification.Name("MacWidgetPowerSourceChanged")
}
