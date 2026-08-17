import Foundation
import Darwin
import os

/// Memory monitor using public APIs only:
/// - Total physical memory: ProcessInfo
/// - Available memory for this process: os_proc_available_memory()
/// - DeviceLab footprint: task_vm_info (phys_footprint) — public Mach API
/// - System page counters: host_statistics64 (free/active/inactive/wired/compressed)
/// Per-app RAM usage of other apps is NOT exposed by iOS public APIs and is never fabricated.
@MainActor
final class MemoryMonitor: BaseMonitor {
    private(set) var availableBytes: UInt64?
    private(set) var footprintBytes: UInt64 = 0
    private(set) var totalBytes: UInt64 = 0
    private(set) var pageCounters: (free: UInt64, active: UInt64, inactive: UInt64, wired: UInt64, compressed: UInt64)?

    init() {
        super.init(kind: .memory)
        totalBytes = ProcessInfo.processInfo.physicalMemory
    }

    override func refresh() async {
        let available = Self.availableMemoryBytes()
        let footprint = Self.footprintBytes()
        let pages = Self.pageCounters()

        availableBytes = available
        footprintBytes = footprint
        pageCounters = pages

        let pageSize = UInt64(vm_kernel_page_size)
        var usedText = ""
        if let pages {
            let used = (pages.active + pages.wired + pages.compressed) * pageSize
            usedText = String(format: "Used ~%.1f GB", Double(used) / 1_073_741_824)
        }

        let status: MetricStatus = {
            guard let available, totalBytes > 0 else { return .inactive }
            let fraction = Double(available) / Double(totalBytes)
            if fraction < 0.1 { return .critical }
            if fraction < 0.2 { return .warning }
            return .normal
        }()

        let detail = """
        Total physical memory: \(Formatters.gigabytes(Double(totalBytes)))
        Available to DeviceLab (os_proc_available_memory): \(available.map { Formatters.gigabytes(Double($0)) } ?? "—")
        DeviceLab footprint (task_vm_info): \(Formatters.megabytes(Double(footprint)))
        System page counters: free \(pages?.free ?? 0), active \(pages?.active ?? 0), inactive \(pages?.inactive ?? 0), wired \(pages?.wired ?? 0), compressed \(pages?.compressed ?? 0)
        Per-app RAM of other apps: not exposed by iOS public APIs.
        """

        updateSnapshot(MetricSnapshot(
            kind: .memory,
            valueText: available.map { Formatters.gigabytes(Double($0)) } ?? "Unavailable",
            subtext: "\(usedText) · DeviceLab \(Formatters.megabytes(Double(footprint)))",
            detail: detail,
            status: status,
            provenance: .systemReported,
            updatedAt: Date(),
            numericValue: available.map { Double($0) / 1_073_741_824 },
            unit: "GB"
        ))
    }

    static func availableMemoryBytes() -> UInt64? {
        let available = os_proc_available_memory()
        guard available > 0 else { return nil }
        return UInt64(available)
    }

    static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { p in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), p, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.phys_footprint)
    }

    static func pageCounters() -> (free: UInt64, active: UInt64, inactive: UInt64, wired: UInt64, compressed: UInt64)? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { p in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, p, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (
            UInt64(stats.free_count),
            UInt64(stats.active_count),
            UInt64(stats.inactive_count),
            UInt64(stats.wire_count),
            UInt64(stats.compressor_page_count)
        )
    }
}