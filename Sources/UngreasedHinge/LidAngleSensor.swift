import Foundation
import IOKit.hid

/// Reads the MacBook lid hinge angle from the Apple SPU HID sensor
/// (usage page 0x20 "Sensor", usage 0x8A "Orientation: Hinge Angle").
final class LidAngleSensor {
    // The manager must stay alive: releasing it closes its devices.
    private let manager: IOHIDManager
    private let device: IOHIDDevice

    init?() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDPrimaryUsagePageKey: 0x20,
            kIOHIDPrimaryUsageKey: 0x8A,
            kIOHIDVendorIDKey: 0x05AC,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>
        else { return nil }

        // Several services match (e.g. AppleSPUHIDDriver and AppleSPUHIDDevice);
        // keep the one that actually answers a feature-report read.
        guard let working = devices.first(where: {
            IOHIDDeviceOpen($0, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
                && Self.readAngle(from: $0) != nil
        }) else { return nil }
        device = working
    }

    private static func readAngle(from device: IOHIDDevice) -> Double? {
        var report = [UInt8](repeating: 0, count: 8)
        var length: CFIndex = report.count
        let status = report.withUnsafeMutableBufferPointer { buffer in
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, buffer.baseAddress!, &length)
        }
        guard status == kIOReturnSuccess, length >= 3 else { return nil }

        // Report layout: [reportID, angleLow, angleHigh]. Some firmware revisions
        // omit the leading report ID byte, so fall back to bytes 0-1 if needed.
        let withIDByte = UInt16(report[1]) | UInt16(report[2]) << 8
        let withoutIDByte = UInt16(report[0]) | UInt16(report[1]) << 8
        for raw in [withIDByte, withoutIDByte] where raw <= 360 {
            return Double(raw)
        }
        return nil
    }

    /// Lid angle in degrees: 0 = closed, ~128 = fully open. nil if the read fails.
    func angleDegrees() -> Double? {
        Self.readAngle(from: device)
    }

    func rawReportHex() -> String {
        var report = [UInt8](repeating: 0, count: 8)
        var length: CFIndex = report.count
        _ = report.withUnsafeMutableBufferPointer { buffer in
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, buffer.baseAddress!, &length)
        }
        return report.prefix(max(length, 0)).map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
