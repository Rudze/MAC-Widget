import Darwin
import Foundation

/// Instantané des ressources du Mac, lu directement par le widget (appels Mach peu coûteux).
struct SystemStats: Hashable {
    var cpu: Double          // 0…1
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var diskUsed: Int64
    var diskTotal: Int64
    var uptime: TimeInterval
    var thermal: ProcessInfo.ThermalState

    var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
    var diskFraction: Double { diskTotal > 0 ? Double(diskUsed) / Double(diskTotal) : 0 }

    var thermalLabel: String {
        switch thermal {
        case .nominal: "Normale"
        case .fair: "Tiède"
        case .serious: "Chaude"
        case .critical: "Critique"
        @unknown default: "—"
        }
    }

    static let placeholder = SystemStats(cpu: 0.23, memoryUsed: 11 << 30, memoryTotal: 16 << 30,
                                         diskUsed: 310 << 30, diskTotal: 494 << 30, uptime: 93_600, thermal: .nominal)

    /// La charge processeur se mesure sur un intervalle : deux relevés espacés de `interval`.
    static func sample(interval: TimeInterval = 0.5) -> SystemStats {
        let first = cpuTicks()
        Thread.sleep(forTimeInterval: interval)
        let second = cpuTicks()
        var cpu = 0.0
        if let a = first, let b = second {
            let busy = Double(b.busy &- a.busy), total = Double(b.total &- a.total)
            cpu = total > 0 ? busy / total : 0
        }

        let (diskUsed, diskTotal) = disk()
        return SystemStats(cpu: min(max(cpu, 0), 1), memoryUsed: memoryUsed(),
                           memoryTotal: ProcessInfo.processInfo.physicalMemory,
                           diskUsed: diskUsed, diskTotal: diskTotal,
                           uptime: ProcessInfo.processInfo.systemUptime,
                           thermal: ProcessInfo.processInfo.thermalState)
    }

    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + nice + idle)
    }

    /// Même définition que « Mémoire utilisée » dans le Moniteur d'activité :
    /// mémoire des apps + mémoire résidente + mémoire compressée.
    private static func memoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let page = UInt64(vm_kernel_page_size)
        let app = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)
        return (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    private static func disk() -> (Int64, Int64) {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return (0, 0) }
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        return (Int64(total) - available, Int64(total))
    }
}
