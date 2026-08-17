import XCTest
@testable import DeviceLab

@MainActor
final class LiveActivityTests: XCTestCase {

    func testAllKindsAreUnique() {
        XCTAssertEqual(DeviceLabActivityKind.allCases.count, 8)
        XCTAssertEqual(Set(DeviceLabActivityKind.allCases.map(\.id)).count, DeviceLabActivityKind.allCases.count)
    }

    func testKindDisplayData() {
        XCTAssertFalse(DeviceLabActivityKind.cpu.displayName.isEmpty)
        XCTAssertFalse(DeviceLabActivityKind.cpu.symbolName.isEmpty)
        XCTAssertEqual(DeviceLabActivityKind.allCases.map(\.displayName).count, 8)
    }

    func testLiveMetricValuesEmptyState() {
        let values = LiveMetricValues()
        XCTAssertNil(values.cpuPercent)
        XCTAssertNil(values.batteryLevel)
        XCTAssertNil(values.networkDownMbps)
        XCTAssertNil(values.thermalStateRaw)
    }

    func testLiveMetricValuesFill() {
        var values = LiveMetricValues()
        values.cpuPercent = 42
        values.batteryLevel = 77
        values.networkDownMbps = 123.4
        values.thermalStateRaw = "Nominal"
        XCTAssertEqual(values.cpuPercent, 42)
        XCTAssertEqual(values.batteryLevel, 77)
        XCTAssertEqual(values.networkDownMbps, 123.4)
        XCTAssertEqual(values.thermalStateRaw, "Nominal")
    }

    func testSettingsPriorityCanBeReordered() {
        let store = SettingsStore()
        let original = store.settings.liveActivityPriority
        store.update { settings in
            settings.liveActivityPriority.reverse()
        }
        XCTAssertNotEqual(store.settings.liveActivityPriority, original)
        XCTAssertEqual(
            Set(store.settings.liveActivityPriority),
            Set(original),
            "Reordering must never drop or duplicate kinds"
        )
    }
}