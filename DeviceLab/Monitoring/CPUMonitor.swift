import Foundation
import Darwin

/// CPU monitor limited to what public APIs allow:
/// - DeviceLab's own process CPU time via getrusage (public Darwin API)
/// - System-wide aggregate CPU load via host_processor_info (public Mach API)
/// Per-app CPU usage of OTHER apps is NOT available and is never fabricated.
@MainActor
final class CPUMonitor: BaseMonitor {
    private var lastSystemTicks: (user: Int, system: Int, idle: Int, nice: Int)?
    private var lastProcessTime: (user: Double, system: Double)?
    private var lastWallTime: ContinuousClock.Instant?

    private(set) var systemPercent: Double?
    private(set) var ownPercent: Double?
    private(set) var ownCumulativeTime: TimeInterval = 0

    override init() {
        super.init(kind: .cpu)
    }

    override func refresh() async {
        let wallNow = ContinuousClock.now
        let wallElapsed: Double = {
            guard let lastWallTime else { return 0 }
            return wallNow.duration(to: lastWallTime).seconds
        }()
        lastWallTime = wallNow

        var processTime: (user: Double, system: Double) = (0, 0)
        var usage = rusage()
        if getrusage(RUSAGE_SELF, &usage) == 0 {
            processTime = (
                Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000,
                Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
            )
        }
        ownCumulativeTime = processTime.user + processTime.system

        if let lastProcessTime, wallElapsed > 0 {
            let delta = (processTime.user + processTime.system) - (lastProcessTime.user + lastProcessTime.system)
            ownPercent = max(0, delta / wallElapsed * 100)
        }
        lastProcessTime = processTime

        if let ticks = Self.systemCPUTicks() {
            if let last = lastSystemTicks {
                let dUser = ticks.user - last.user
                let dSystem = ticks.system - last.system
                let dIdle = ticks.idle - last.idle
                let dNice = ticks.nice - last.nice
                let total = dUser + dSystem + dIdle + dNice
                if total > 0 {
                    systemPercent = min(100, max(0, Double(dUser + dSystem + dNice) / Double(total) * 100))
                }
            }
            lastSystemTicks = ticks
        }

        let cores = ProcessInfo.processInfo.activeProcessorCount
        var subtext = "System total"
        var numeric = systemPercent ?? 0
        if let systemPercent {
            subtext = String(format: "System total %.0f%% · %d cores", systemPercent, cores)
        } else {
            subtext = "\(cores) cores"
        }
        if let ownPercent {
            subtext += String(format: " · DeviceLab %.0f%%", ownPercent)
        }

        let status: MetricStatus = {
            guard let systemPercent else { return .inactive }
            if systemPercent > 90 { return .critical }
            if systemPercent > 70 { return .warning }
            return .normal
        }()

        let detail = """
        System-wide CPU load (kernel counters, public API): \(systemPercent.map { String(format: "%.0f%%", $0) } ?? "—")
        DeviceLab CPU (getrusage): \(ownPercent.map { String(format: "%.0f%%", $0) } ?? "—") relative to one core
        DeviceLab cumulative CPU time: \(String(format: "%.1f s", ownCumulativeTime))
        Per-app CPU for other apps: not exposed by iOS public APIs.
        """

        updateSnapshot(MetricSnapshot(
            kind: .cpu,
            valueText: systemPercent.map { String(format: "%.0f%%", $0) } ?? "Unavailable",
            subtext: subtext,
            detail: detail,
            status: status,
            provenance: .systemReported,
            updatedAt: Date(),
            numericValue: numeric,
            unit: "%"
        ))
    }

    /// Aggregate CPU ticks across all cores (public Mach API: host_processor_info).
    static func systemCPUTicks() -> (user: Int, system: Int, idle: Int, nice: Int)? {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCpuInfo)
        guard result == KERN_SUCCESS, let info = cpuInfo else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        var user = 0, system = 0, idle = 0, nice = 0
        let stateMax = Int(CPU_STATE_MAX)
        for i in 0..<Int(numCPUs) {
            let offset = stateMax * i
            user += Int(info[offset + Int(CPU_STATE_USER)])
            system += Int(info[offset + Int(CPU_STATE_SYSTEM)])
            idle += Int(info[offset + Int(CPU_STATE_IDLE)])
            nice += Int(info[offset + Int(CPU_STATE_NICE)])
        }
        return (user, system, idle, nice)
    }
}