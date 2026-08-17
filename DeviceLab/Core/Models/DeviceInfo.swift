import Foundation
import UIKit

/// Static device facts collected from public APIs.
struct DeviceInfo {
    let marketingName: String
    let modelIdentifier: String
    let systemName: String
    let systemVersion: String
    let physicalMemoryBytes: UInt64
    let processorCount: Int
    let machineArchitecture: String

    static let current = DeviceInfo()

    private init() {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }

        marketingName = Self.marketingName(for: machine)
        modelIdentifier = machine
        systemName = UIDevice.current.systemName
        systemVersion = UIDevice.current.systemVersion
        physicalMemoryBytes = ProcessInfo.processInfo.physicalMemory
        processorCount = ProcessInfo.processInfo.activeProcessorCount
        machineArchitecture = withUnsafePointer(to: &systemInfo.machine) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
    }

    var osLabel: String { "\(systemName) \(systemVersion)" }

    var memoryGB: Double { Double(physicalMemoryBytes) / 1_073_741_824 }

    /// Marketing names derived from the hardware model identifier (sysctl).
    static func marketingName(for identifier: String) -> String {
        switch identifier {
        case "iPhone15,2": return "iPhone 15 Pro"
        case "iPhone15,3": return "iPhone 15 Pro Max"
        case "iPhone15,4": return "iPhone 15"
        case "iPhone15,5": return "iPhone 15 Plus"
        case "iPhone16,1": return "iPhone 16 Pro"
        case "iPhone16,2": return "iPhone 16 Pro Max"
        case "iPhone16,3": return "iPhone 16"
        case "iPhone16,4": return "iPhone 16 Plus"
        case "iPhone17,1": return "iPhone 17 Pro"
        case "iPhone17,2": return "iPhone 17 Pro Max"
        case "iPhone17,3": return "iPhone 17"
        case "iPhone17,4": return "iPhone 17 Air"
        default: return identifier
        }
    }
}