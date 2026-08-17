import Foundation

/// Storage monitor.
/// Total/available capacity comes from the volume resource values API (public).
/// DeviceLab sandbox usage is measured by enumerating its own containers.
/// Other apps' directories are protected and never scanned.
@MainActor
final class StorageMonitor: BaseMonitor {
    private(set) var totalBytes: UInt64 = 0
    private(set) var availableBytes: UInt64 = 0
    private(set) var appSandboxBytes: UInt64 = 0
    private(set) var documentsBytes: UInt64 = 0
    private(set) var cachesBytes: UInt64 = 0
    private(set) var temporaryBytes: UInt64 = 0
    private(set) var fileCount: Int = 0

    init() {
        super.init(kind: .storage)
        if let info = Self.volumeInfo() {
            totalBytes = UInt64(info.total)
            availableBytes = UInt64(info.available)
        }
    }

    override func refresh() async {
        if let info = Self.volumeInfo() {
            totalBytes = UInt64(info.total)
            availableBytes = UInt64(info.available)
        }

        let sizes = Self.sandboxSizes()
        documentsBytes = sizes.documents
        cachesBytes = sizes.caches
        temporaryBytes = sizes.temporary
        appSandboxBytes = sizes.documents + sizes.caches + sizes.temporary
        fileCount = sizes.fileCount

        let used = totalBytes > availableBytes ? totalBytes - availableBytes : 0
        let status: MetricStatus = {
            guard totalBytes > 0 else { return .inactive }
            let freeFraction = Double(availableBytes) / Double(totalBytes)
            if freeFraction < 0.05 { return .critical }
            if freeFraction < 0.10 { return .warning }
            return .normal
        }()

        let detail = """
        Total capacity: \(Formatters.gigabytes(Double(totalBytes)))
        Free: \(Formatters.gigabytes(Double(availableBytes)))
        Used: \(Formatters.gigabytes(Double(used)))

        DeviceLab sandbox:
        Documents \(Formatters.megabytes(Double(documentsBytes)))
        Caches \(Formatters.megabytes(Double(cachesBytes)))
        Temporary \(Formatters.megabytes(Double(temporaryBytes)))
        Files in sandbox: \(fileCount)

        Other apps' storage usage is protected by iOS and not readable.
        """

        updateSnapshot(MetricSnapshot(
            kind: .storage,
            valueText: Formatters.gigabytes(Double(availableBytes)),
            subtext: "\(Formatters.gigabytes(Double(used))) used of \(Formatters.gigabytes(Double(totalBytes)))",
            detail: detail,
            status: status,
            provenance: .directPublicAPI,
            updatedAt: Date(),
            numericValue: Double(availableBytes) / 1_073_741_824,
            unit: "GB"
        ))
    }

    nonisolated static func volumeInfo() -> (total: Int64, available: Int64)? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return (Int64(total), Int64(available))
    }

    /// Enumerates only DeviceLab's own sandbox containers.
    static func sandboxSizes() -> (documents: UInt64, caches: UInt64, temporary: UInt64, fileCount: Int) {
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        let temporary = fileManager.temporaryDirectory

        func size(of url: URL) -> (bytes: UInt64, files: Int) {
            guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                return (0, 0)
            }
            var bytes: UInt64 = 0
            var files = 0
            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values?.isRegularFile == true {
                    bytes += UInt64(values?.fileSize ?? 0)
                    files += 1
                }
            }
            return (bytes, files)
        }

        let doc = documents.map { size(of: $0) } ?? (0, 0)
        let cache = caches.map { size(of: $0) } ?? (0, 0)
        let tmp = size(of: temporary)
        return (doc.bytes, cache.bytes, tmp.bytes, doc.files + cache.files + tmp.files)
    }
}