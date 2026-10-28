import SwiftUI
import WidgetKit

struct BatteryEntry: TimelineEntry {
    let date: Date
    let devices: [BatteryDevice]
    var style = Appearance().battery
}

struct BatteryProvider: TimelineProvider {
    static let sample = [
        BatteryDevice(id: "mac", name: "MacBook", kind: .mac, level: 82, isCharging: true),
        BatteryDevice(id: "l", name: "AirPods Pro", kind: .earbuds, level: 64, isCharging: false),
        BatteryDevice(id: "c", name: "Boîtier", kind: .earbudsCase, level: 40, isCharging: false),
        BatteryDevice(id: "k", name: "Magic Keyboard", kind: .keyboard, level: 91, isCharging: false),
    ]

    func placeholder(in context: Context) -> BatteryEntry { BatteryEntry(date: .now, devices: Self.sample) }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        let entry = load()
        completion(context.isPreview && entry.devices.isEmpty ? placeholder(in: context) : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    /// L'app met à jour le JSON ; la batterie du Mac est relue en direct si possible.
    private func load() -> BatteryEntry {
        let snapshot = SharedStore.read(BatterySnapshot.self, from: SharedStore.batteryFile)
        var devices = snapshot?.devices ?? []
        // Données trop vieilles (app quittée) : on ne garde que le Mac.
        if let s = snapshot, Date().timeIntervalSince(s.updated) > 3600 {
            devices = devices.filter { $0.kind == .mac }
        }
        let macName = devices.first { $0.kind == .mac }?.name ?? "Mac"
        if let live = MacBattery.read(name: macName) {
            devices.removeAll { $0.kind == .mac }
            devices.insert(live, at: 0)
        }
        return BatteryEntry(date: .now, devices: devices, style: Appearance.current.battery)
    }
}

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.battery, provider: BatteryProvider()) { entry in
            BatteryView(entry: entry)
        }
        .configurationDisplayName("Batteries")
        .description("La charge de ton Mac et de tes appareils Bluetooth, en blanc.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct BatteryRing: View {
    let device: BatteryDevice
    let size: CGFloat

    private var line: CGFloat { max(size * 0.085, 3.5) }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: line)
            Circle()
                .trim(from: 0, to: CGFloat(device.level) / 100)
                .stroke(Theme.primary, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            Image(systemName: device.kind.symbol)
                .font(.system(size: size * 0.34, weight: .regular))
                .foregroundStyle(Theme.primary)
            if device.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: max(size * 0.17, 8), weight: .bold))
                    .foregroundStyle(Theme.primary)
                    .padding(2)
                    .background(Circle().fill(Color(white: 0.1)))
                    .offset(y: -size / 2)
            }
        }
        .frame(width: size, height: size)
    }
}

struct BatteryView: View {
    let entry: BatteryEntry
    @ResolvedFamily private var family

    var body: some View {
        Group {
            if entry.devices.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "battery.0percent").font(.title2)
                    Text("Aucun appareil").font(.caption)
                }
                .foregroundStyle(Theme.secondary)
            } else {
                switch family {
                case .systemSmall: small
                case .systemLarge: large
                default: medium
                }
            }
        }
        .foregroundStyle(Theme.primary)
        .widgetBackground(entry.style)
    }

    private func percent(_ d: BatteryDevice, size: CGFloat) -> some View {
        Text("\(d.level) %")
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
    }

    @ViewBuilder private var small: some View {
        let devices = Array(entry.devices.prefix(4))
        if devices.count == 1, let d = devices.first {
            VStack(spacing: 10) {
                BatteryRing(device: d, size: 88)
                percent(d, size: 22)
            }
        } else if devices.count == 2 {
            HStack(spacing: 14) {
                ForEach(devices) { d in
                    VStack(spacing: 8) {
                        BatteryRing(device: d, size: 56)
                        percent(d, size: 15)
                    }
                }
            }
        } else {
            Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow { ring(devices, 0); ring(devices, 1) }
                GridRow { ring(devices, 2); ring(devices, 3) }
            }
        }
    }

    @ViewBuilder private func ring(_ devices: [BatteryDevice], _ i: Int) -> some View {
        if i < devices.count { BatteryRing(device: devices[i], size: 54) } else { Color.clear.frame(width: 54, height: 54) }
    }

    private var medium: some View {
        HStack(spacing: 0) {
            ForEach(entry.devices.prefix(4)) { d in
                VStack(spacing: 10) {
                    BatteryRing(device: d, size: 60)
                    percent(d, size: 16)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var large: some View {
        VStack(spacing: 0) {
            ForEach(Array(entry.devices.prefix(6).enumerated()), id: \.element.id) { index, d in
                if index > 0 { Divider().overlay(Theme.track) }
                HStack(spacing: 14) {
                    BatteryRing(device: d, size: 40)
                    Text(d.name)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    percent(d, size: 17)
                }
                .frame(maxHeight: .infinity)
            }
            if entry.devices.count < 6 { Spacer(minLength: 0) }
        }
    }
}
