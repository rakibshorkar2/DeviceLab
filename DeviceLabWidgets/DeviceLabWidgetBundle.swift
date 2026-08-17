import WidgetKit
import SwiftUI

@main
struct DeviceLabWidgetBundle: WidgetBundle {
    var body: some Widget {
        DeviceLabSnapshotWidget()
        DeviceLabLiveActivity()
    }
}