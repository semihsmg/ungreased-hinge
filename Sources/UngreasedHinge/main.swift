import Foundation

let debug = CommandLine.arguments.contains("--debug")

// Toggle behavior: if an instance is already running, stop it and exit.
let pidFileURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("ungreased-hinge.pid")

if let pidText = try? String(contentsOf: pidFileURL, encoding: .utf8),
   let existingPID = Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)),
   kill(existingPID, 0) == 0 {
    kill(existingPID, SIGTERM)
    try? FileManager.default.removeItem(at: pidFileURL)
    print("ungreased-hinge: stopped running instance (pid \(existingPID))")
    exit(0)
}

try? "\(getpid())".write(to: pidFileURL, atomically: true, encoding: .utf8)

func handleTerminationSignal(_ signalNumber: Int32) {
    try? FileManager.default.removeItem(at: pidFileURL)
    exit(0)
}
signal(SIGTERM, handleTerminationSignal)
signal(SIGINT, handleTerminationSignal)

guard let sensor = LidAngleSensor() else {
    fputs("error: lid angle sensor not found (requires a MacBook with the hinge angle sensor)\n", stderr)
    exit(1)
}

let player: CreakPlayer
do {
    player = try CreakPlayer()
} catch {
    fputs("error: audio setup failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}

// Quiesce audio around sleep/wake: touching AVFoundation while the output
// device is mid-teardown raises an uncatchable NSException (see CreakPlayer).
let sleepWakeObserver = SleepWakeObserver()
if let sleepWakeObserver {
    sleepWakeObserver.onSleep = { player.suspend() }
    sleepWakeObserver.onWake = { player.resume() }
} else {
    fputs("warning: could not register for sleep/wake notifications\n", stderr)
}

guard var lastAngle = sensor.angleDegrees() else {
    fputs("error: sensor found but angle read failed (raw report: \(sensor.rawReportHex()))\n", stderr)
    exit(1)
}

print(String(format: "ungreased-hinge: creaking armed. current lid angle: %.0f°  (ctrl-c to quit)", lastAngle))

// Poll fast only while the lid is moving; a still lid is checked at a low
// rate (worst case the creak starts ~125ms into a movement). Generous leeway
// lets the OS coalesce the idle wakeups with other system activity.
let activePollInterval = 1.0 / 60.0
let idlePollInterval = 1.0 / 8.0
let idleAfterSeconds = 2.0

var smoothedVelocity = 0.0
var lastSampleTime = ProcessInfo.processInfo.systemUptime
var lastMovementTime = lastSampleTime
var pollingFast = true

let timer = DispatchSource.makeTimerSource(queue: .main)

func applyPollingRate() {
    let interval = pollingFast ? activePollInterval : idlePollInterval
    timer.schedule(deadline: .now() + interval, repeating: interval,
                   leeway: .milliseconds(pollingFast ? 5 : 50))
}

timer.setEventHandler {
    guard let angle = sensor.angleDegrees() else { return }
    let now = ProcessInfo.processInfo.systemUptime
    // Use measured elapsed time: the interval varies with polling rate and leeway.
    let elapsed = now - lastSampleTime
    lastSampleTime = now
    // Clamp out occasional sensor glitches that read as impossible jumps.
    let rawVelocity = max(-400, min(400, (angle - lastAngle) / elapsed))
    lastAngle = angle
    smoothedVelocity += (rawVelocity - smoothedVelocity) * 0.4
    player.update(velocityDegreesPerSecond: smoothedVelocity)

    if abs(rawVelocity) > CreakPlayer.movementThreshold {
        lastMovementTime = now
    }
    let shouldPollFast = now - lastMovementTime < idleAfterSeconds
    if shouldPollFast != pollingFast {
        pollingFast = shouldPollFast
        applyPollingRate()
    }

    if debug {
        print(String(format: "angle: %6.1f°  velocity: %+7.1f°/s  poll: %@  raw: %@",
                     angle, smoothedVelocity, pollingFast ? "fast" : "idle",
                     sensor.rawReportHex()))
    }
}
applyPollingRate()
timer.resume()
dispatchMain()
