import AppKit
import SwiftUI
import WidgetKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let settings = AppSettings.shared
    let battery = BatteryMonitor()
    let calendar = CalendarSync()
    let photos = PhotoLibrary()
    let wallpaper = WallpaperController()
    let navigation = Navigation()
    let appearance = AppearanceStore()
    let github = GitHubSync()
    let music = MusicController()
    lazy var floating = FloatingWidgets(battery: battery, github: github, appearance: appearance, photos: photos, music: music)

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var wallpaperItem: NSMenuItem?
    private var moveItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: SharedStore.photosDirectory, withIntermediateDirectories: true)
        battery.start()
        calendar.start()
        github.start()
        music.start()
        floating.start()
        wallpaper.start()
        updateStatusItem()
        WidgetCenter.shared.reloadAllTimelines()

        if !settings.didOnboard {
            settings.didOnboard = true
            if !settings.launchAtLogin { settings.launchAtLogin = true }
            openSettings()
        }
    }

    /// Relancer l'app (Finder, Spotlight) ouvre les réglages, utile si l'icône est masquée.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first, url.scheme == "macwidget" else { return }
        switch url.host {
        case "photos":
            navigation.section = .photos
            if let slot = Int(url.lastPathComponent), (0..<WidgetKinds.photoSlotCount).contains(slot) {
                navigation.photoSlot = slot
            }
        case "open":
            if let link = WidgetLink(rawValue: url.lastPathComponent) { open(link) }
            return
        case "music":
            // Bouton du widget : on exécute la commande et on rend la main à l'app précédente.
            if let command = MusicCommand(rawValue: url.lastPathComponent) { music.send(command) }
            if settingsWindow?.isVisible != true { NSApp.hide(nil) }
            return
        default: break
        }
        openSettings()
    }

    /// Clic sur un widget : on ouvre directement l'app ou la page correspondante.
    func open(_ link: WidgetLink) {
        switch link {
        case .calendar: openApp("com.apple.iCal")
        case .activity: openApp("com.apple.ActivityMonitor")
        case .github:
            let user = github.username.trimmingCharacters(in: .whitespaces)
            if user.isEmpty {
                navigation.section = .github
                openSettings()
            } else if let page = URL(string: "https://github.com/\(user)") {
                NSWorkspace.shared.open(page)
            }
        }
    }

    private func openApp(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Barre des menus

    func updateStatusItem() {
        if settings.hideMenuBarIcon {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "MacWidget")

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Réglages de MacWidget…", action: #selector(openSettingsAction), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        let wallpaperItem = menu.addItem(withTitle: "Fond d'écran animé", action: #selector(toggleWallpaper), keyEquivalent: "")
        wallpaperItem.target = self
        self.wallpaperItem = wallpaperItem
        let moveItem = menu.addItem(withTitle: "Déplacer les widgets flottants", action: #selector(toggleMoving), keyEquivalent: "")
        moveItem.target = self
        self.moveItem = moveItem
        menu.addItem(withTitle: "Actualiser les widgets", action: #selector(refreshWidgets), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter MacWidget", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        wallpaperItem?.state = settings.wallpaperEnabled ? .on : .off
        wallpaperItem?.isEnabled = settings.wallpaperPath != nil
        moveItem?.state = floating.editing ? .on : .off
        moveItem?.isHidden = !floating.anyShown
    }

    @objc private func openSettingsAction() { openSettings() }

    @objc private func toggleWallpaper() { settings.wallpaperEnabled.toggle() }

    @objc private func toggleMoving() { floating.editing.toggle() }

    @objc private func refreshWidgets() {
        battery.refresh()
        calendar.sync()
        github.refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Fenêtre de réglages (créée à la demande, libérée à la fermeture)

    func openSettings() {
        if settingsWindow == nil {
            let root = SettingsView()
                .environmentObject(settings)
                .environmentObject(battery)
                .environmentObject(calendar)
                .environmentObject(photos)
                .environmentObject(wallpaper)
                .environmentObject(navigation)
                .environmentObject(appearance)
                .environmentObject(github)
                .environmentObject(floating)
                .environment(\.updateMenuBarIcon) { [weak self] in self?.updateStatusItem() }
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "MacWidget"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 820, height: 580))
            window.minSize = NSSize(width: 720, height: 500)
            window.isReleasedWhenClosed = false
            window.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.settingsWindow = nil
                    NSApp.setActivationPolicy(.accessory)
                }
            }
            settingsWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class Navigation: ObservableObject {
    @Published var section: SettingsSection = .widgets
    @Published var photoSlot = 0
}

private struct UpdateMenuBarIconKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var updateMenuBarIcon: () -> Void {
        get { self[UpdateMenuBarIconKey.self] }
        set { self[UpdateMenuBarIconKey.self] = newValue }
    }
}
