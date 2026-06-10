import Foundation
import IOKit
import IOKit.pwr_mgt

/// Calls back around system sleep/wake via IOKit root-domain power
/// notifications, delivered on the main queue (no runloop needed, so it
/// works under dispatchMain()).
final class SleepWakeObserver {
    // The kIOMessage* macros from IOMessage.h don't import into Swift
    // (iokit_common_msg is a function-like macro). sys_iokit = 0xE0000000.
    private static let messageCanSystemSleep: UInt32 = 0xE0000270
    private static let messageSystemWillSleep: UInt32 = 0xE0000280
    private static let messageSystemHasPoweredOn: UInt32 = 0xE0000300

    var onSleep: (() -> Void)?
    var onWake: (() -> Void)?

    private var rootPort: io_connect_t = 0
    private var notifier: io_object_t = 0

    init?() {
        var notificationPort: IONotificationPortRef?
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(refcon, &notificationPort, { refcon, _, messageType, messageArgument in
            guard let refcon else { return }
            Unmanaged<SleepWakeObserver>.fromOpaque(refcon).takeUnretainedValue()
                .handle(messageType: messageType, messageArgument: messageArgument)
        }, &notifier)
        guard rootPort != 0, let notificationPort else { return nil }
        IONotificationPortSetDispatchQueue(notificationPort, .main)
    }

    private func handle(messageType: UInt32, messageArgument: UnsafeMutableRawPointer?) {
        switch messageType {
        case Self.messageCanSystemSleep:
            // Unanswered sleep queries delay sleep by 30 seconds.
            IOAllowPowerChange(rootPort, Int(bitPattern: messageArgument))
        case Self.messageSystemWillSleep:
            onSleep?()
            IOAllowPowerChange(rootPort, Int(bitPattern: messageArgument))
        case Self.messageSystemHasPoweredOn:
            onWake?()
        default:
            break
        }
    }
}
