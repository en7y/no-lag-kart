// Lists the controllers macOS's GameController framework sees, and which profile each one has.
// nxnative's Mac host uses a controller only when it has an extended gamepad profile (dm/host/front_mac.m).
// Usage: swift mkw/pads.swift   (connect the controllers first)
import GameController
import Foundation
GCController.shouldMonitorBackgroundEvents = true
RunLoop.current.run(until: Date().addingTimeInterval(3.0))
let all = GCController.controllers()
print("controllers: \(all.count)")
for c in all {
    print("- \(c.vendorName ?? "?") | category: \(c.productCategory) | extended profile: \(c.extendedGamepad != nil) | micro profile: \(c.microGamepad != nil) | gyro: \(c.motion?.hasRotationRate ?? false) | rumble: \(c.haptics != nil)")
    print("  elements: " + c.physicalInputProfile.elements.keys.sorted().joined(separator: ", "))
}
