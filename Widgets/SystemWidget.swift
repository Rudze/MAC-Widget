import SwiftUI
import WidgetKit

struct SystemEntry: TimelineEntry {
    let date: Date
    let stats: SystemStats
    let battery: BatteryDevice?
    var style = Appearance().system
}

struct SystemProvider: TimelineProvider {
    func placeholder(in context: Context) -> SystemEntry {
        SystemEntry(date: .now, stats: .placeholder,
                    battery: BatteryDevice(id: "mac", name: "Mac", kind: .mac, level: 76, isCharging: false))
    }

    func getSnapshot(in context: Context, completion: @escaping (SystemEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : load())
    }

    /// Relevé fait par l'extension elle-même, environ toutes les 5 min
    /// (WidgetKit ne permet pas d'animer en continu, et ce serait coûteux).
    func getTimeline(in context: Context, completion: @escaping (Timeline<SystemEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .after(.now.addingTimeInterval(5 * 60))))
    }

    private func load() -> SystemEntry {
        SystemEntry(date: .now, stats: .sample(), battery: MacBattery.read(), style: Appearance.current.system)
    }
}

struct SystemWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.system, provider: SystemProvider()) { entry in
            SystemView(entry: entry)
        }
        .configurationDisplayName("Ressources")
        .description("Processeur, mémoire, stockage et batterie du Mac.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct Metric: Identifiable {
    let id: String
    let symbol: String
    let label: String
    let fraction: Double
    let detail: String
}

struct SystemView: View {
    let entry: SystemEntry
    @ResolvedFamily private var family

    private var metrics: [Metric] {
        let s = entry.stats
        var list = [
            Metric(id: "cpu", symbol: "cpu", label: "Processeur", fraction: s.cpu, detail: percent(s.cpu)),
            Metric(id: "ram", symbol: "memorychip", label: "Mémoire", fraction: s.memoryFraction,
                   detail: "\(bytes(Int64(s.memoryUsed))) / \(bytes(Int64(s.memoryTotal)))"),
            Metric(id: "disk", symbol: "internaldrive", label: "Stockage", fraction: s.diskFraction,
                   detail: "\(bytes(s.diskTotal - s.diskUsed)) libres"),
        ]
        if let b = entry.battery {
            list.append(Metric(id: "bat", symbol: b.isCharging ? "battery.100percent.bolt" : "battery.75percent",
                               label: "Batterie", fraction: Double(b.level) / 100, detail: "\(b.level) %"))
        }
        return list
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            case .systemLarge: large
            default: medium
            }
        }
        .foregroundStyle(Theme.primary)
        .widgetBackground(entry.style)
        .widgetURL(WidgetLink.activity.url)
    }

    private var small: some View {
        let items = Array(metrics.prefix(4))
        return Grid(horizontalSpacing: 14, verticalSpacing: 12) {
            GridRow { ring(items, 0); ring(items, 1) }
            GridRow { ring(items, 2); ring(items, 3) }
        }
    }

    @ViewBuilder private func ring(_ items: [Metric], _ i: Int) -> some View {
        if i < items.count {
            VStack(spacing: 4) {
                GaugeRing(fraction: items[i].fraction, symbol: items[i].symbol, size: 46)
                Text(percent(items[i].fraction))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        } else {
            Color.clear.frame(width: 46, height: 46)
        }
    }

    private var medium: some View {
        HStack(spacing: 0) {
            ForEach(metrics) { m in
                VStack(spacing: 8) {
                    GaugeRing(fraction: m.fraction, symbol: m.symbol, size: 56)
                    VStack(spacing: 1) {
                        Text(percent(m.fraction))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(m.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Ressources").font(.system(size: 15, weight: .semibold))
                Spacer()
                Label("Température \(entry.stats.thermalLabel.lowercased())", systemImage: "thermometer.medium")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }
            ForEach(metrics) { m in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(m.label, systemImage: m.symbol).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(m.detail)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.track)
                            Capsule().fill(Theme.primary)
                                .frame(width: max(geo.size.width * m.fraction, 6))
                                .widgetAccentable()
                        }
                    }
                    .frame(height: 6)
                }
            }
            Spacer(minLength: 0)
            Text("Allumé depuis \(uptime(entry.stats.uptime)) · relevé à \(entry.date.hm)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiary)
        }
    }

    private func percent(_ f: Double) -> String { "\(Int((f * 100).rounded())) %" }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .memory)
    }

    private func uptime(_ t: TimeInterval) -> String {
        let days = Int(t) / 86_400, hours = Int(t) % 86_400 / 3600, minutes = Int(t) % 3600 / 60
        return days > 0 ? "\(days) j \(hours) h" : "\(hours) h \(minutes) min"
    }
}

struct GaugeRing: View {
    let fraction: Double
    let symbol: String
    let size: CGFloat

    private var line: CGFloat { max(size * 0.085, 3.5) }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: line)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0.005), 1))
                .stroke(Theme.primary, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            Image(systemName: symbol)
                .font(.system(size: size * 0.32))
        }
        .frame(width: size, height: size)
    }
}
