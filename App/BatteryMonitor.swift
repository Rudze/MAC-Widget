import Foundation
import IOBluetooth
import IOKit
import IOKit.ps
import WidgetKit

/// Collecte les niveaux de batterie (Mac, accessoires HID Bluetooth, écouteurs)
/// et les publie pour le widget. Piloté par notifications, avec un timer lent en secours.
@MainActor
final class BatteryMonitor: NSObject, ObservableObject {
    @Published private(set) var devices: [BatteryDevice] = []

    private let macName = Host.current().localizedName ?? "Mac"
    private var powerSource: CFRunLoopSource?
    private var timer: Timer?
    private var connectNotification: IOBluetoothUserNotification?
    private var profilerDevices: [BatteryDevice] = []
    private var profilerDate = Date.distantPast
    private var profilerRunning = false
    private var reloaded: [BatteryDevice] = []
    private var reloadDate = Date.distantPast

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                NotificationCenter.default.post(name: .powerSourceChanged, object: nil)
                monitor.refresh()
            }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }

        let timer = Timer(timeInterval: 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(bluetoothConnected(_:device:)))
        refresh()
    }

    @objc private func bluetoothConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(bluetoothDisconnected(_:device:)))
        profilerDate = .distantPast
        // Les niveaux arrivent quelques secondes après la connexion.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.refresh() }
    }

    @objc private func bluetoothDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        profilerDevices.removeAll { $0.name == device.name || $0.name.hasPrefix((device.name ?? "") + " ") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refresh() }
    }

    func refresh() {
        var list: [BatteryDevice] = []
        if let mac = MacBattery.read(name: macName) { list.append(mac) }
        let hid = HIDBatteries.read()
        list += hid
        let bluetooth = BluetoothBatteries.readConnected(excluding: Set(hid.map(\.name)))
        list += bluetooth.devices

        if bluetooth.unresolvedAudio {
            list += profilerDevices.filter { d in !list.contains { $0.name == d.name } }
            fetchProfilerIfNeeded()
        } else {
            profilerDevices = []
        }
        publish(list)
    }

    /// Repli pour les écouteurs dont IOBluetooth ne donne pas le niveau :
    /// `system_profiler` est coûteux, donc au plus une fois toutes les 5 min.
    private func fetchProfilerIfNeeded() {
        guard !profilerRunning, Date().timeIntervalSince(profilerDate) > 300 else { return }
        profilerRunning = true
        DispatchQueue.global(qos: .utility).async {
            let devices = BluetoothBatteries.readFromSystemProfiler()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.profilerRunning = false
                self.profilerDate = Date()
                self.profilerDevices = devices
                self.refresh()
            }
        }
    }

    private func publish(_ list: [BatteryDevice]) {
        let sorted = list.sorted { ($0.kind.sortOrder, $0.name) < ($1.kind.sortOrder, $1.name) }
        guard sorted != devices else { return }
        devices = sorted
        SharedStore.write(BatterySnapshot(devices: sorted, updated: Date()), to: SharedStore.batteryFile)

        // Économise le budget de rafraîchissement de WidgetKit : immédiat si un appareil
        // apparaît/disparaît ou change d'état de charge, sinon tous les 2 % au plus toutes les 5 min.
        let structural = sorted.map { "\($0.id)\($0.isCharging)" } != reloaded.map { "\($0.id)\($0.isCharging)" }
        let drift = zip(sorted, reloaded).contains { abs($0.level - $1.level) >= 2 }
        if structural || (drift && Date().timeIntervalSince(reloadDate) > 300) {
            reloaded = sorted
            reloadDate = Date()
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.battery)
        }
    }
}

// MARK: - Clavier / souris / trackpad Apple

enum HIDBatteries {
    static func read() -> [BatteryDevice] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var seen = Set<String>()
        var result: [BatteryDevice] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let level = property(service, "BatteryPercent") as? Int,
                  let product = property(service, "Product") as? String,
                  !product.localizedCaseInsensitiveContains("internal")
            else { continue }
            let key = property(service, "DeviceAddress") as? String ?? product
            guard seen.insert(key).inserted else { continue }

            let lower = product.lowercased()
            let kind: DeviceKind = lower.contains("keyboard") ? .keyboard
                : lower.contains("mouse") ? .mouse
                : lower.contains("trackpad") ? .trackpad
                : .other
            let flags = property(service, "BatteryStatusFlags") as? Int ?? 0
            result.append(BatteryDevice(id: "hid-\(key)", name: product, kind: kind,
                                        level: min(max(level, 0), 100), isCharging: flags == 3))
        }
        return result
    }

    private static func property(_ service: io_object_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

// MARK: - Écouteurs, casques, manettes

enum BluetoothBatteries {
    struct Result {
        var devices: [BatteryDevice] = []
        var unresolvedAudio = false
    }

    private static let audioMajorClass = 0x04

    static func readConnected(excluding names: Set<String>) -> Result {
        var result = Result()
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return result }

        for device in paired where device.isConnected() {
            let name = device.name ?? "Appareil Bluetooth"
            guard !names.contains(name) else { continue }
            let address = device.addressString ?? name
            let isAudio = Int(device.deviceClassMajor) == audioMajorClass

            let left = percent(device, "batteryPercentLeft")
            let right = percent(device, "batteryPercentRight")
            let caseLevel = percent(device, "batteryPercentCase")
            let single = percent(device, "batteryPercentSingle") ?? percent(device, "batteryPercentCombined")

            if left != nil || right != nil {
                let level = [left, right].compactMap { $0 }.min() ?? 0
                result.devices.append(BatteryDevice(id: "bt-\(address)", name: name, kind: .earbuds,
                                                    level: level, isCharging: false))
                if let caseLevel {
                    result.devices.append(BatteryDevice(id: "bt-\(address)-case", name: "\(name) (boîtier)",
                                                        kind: .earbudsCase, level: caseLevel, isCharging: false))
                }
            } else if let single {
                let kind: DeviceKind = isAudio ? .headphones
                    : name.localizedCaseInsensitiveContains("controller") ? .controller : .other
                result.devices.append(BatteryDevice(id: "bt-\(address)", name: name, kind: kind,
                                                    level: single, isCharging: false))
            } else if isAudio {
                result.unresolvedAudio = true
            }
        }
        return result
    }

    /// Propriétés non documentées d'IOBluetoothDevice : vérifiées avant lecture.
    private static func percent(_ device: IOBluetoothDevice, _ key: String) -> Int? {
        guard device.responds(to: NSSelectorFromString(key)),
              let value = (device.value(forKey: key) as? NSNumber)?.intValue,
              value > 0 else { return nil }
        return min(value, 100)
    }

    static func readFromSystemProfiler() -> [BatteryDevice] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }

        var result: [BatteryDevice] = []
        for section in sections {
            for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    let address = info["device_address"] as? String ?? name
                    let left = number(info["device_batteryLevelLeft"])
                    let right = number(info["device_batteryLevelRight"])
                    let caseLevel = number(info["device_batteryLevelCase"])
                    let main = number(info["device_batteryLevelMain"])
                    if left != nil || right != nil {
                        result.append(BatteryDevice(id: "bt-\(address)", name: name, kind: .earbuds,
                                                    level: [left, right].compactMap { $0 }.min() ?? 0,
                                                    isCharging: false))
                        if let caseLevel {
                            result.append(BatteryDevice(id: "bt-\(address)-case", name: "\(name) (boîtier)",
                                                        kind: .earbudsCase, level: caseLevel, isCharging: false))
                        }
                    } else if let main {
                        result.append(BatteryDevice(id: "bt-\(address)", name: name, kind: .headphones,
                                                    level: main, isCharging: false))
                    }
                }
            }
        }
        return result
    }

    private static func number(_ value: Any?) -> Int? {
        guard let s = value as? String else { return nil }
        return Int(s.filter(\.isNumber))
    }
}
