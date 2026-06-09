import Foundation

let debug = CommandLine.arguments.contains("--debug")

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

guard var lastAngle = sensor.angleDegrees() else {
    fputs("error: sensor found but angle read failed (raw report: \(sensor.rawReportHex()))\n", stderr)
    exit(1)
}

print(String(format: "ungreased-hinge: creaking armed. current lid angle: %.0f°  (ctrl-c to quit)", lastAngle))

let pollInterval = 1.0 / 60.0
var smoothedVelocity = 0.0

let timer = Timer(timeInterval: pollInterval, repeats: true) { _ in
    guard let angle = sensor.angleDegrees() else { return }
    // Clamp out occasional sensor glitches that read as impossible jumps.
    let rawVelocity = max(-400, min(400, (angle - lastAngle) / pollInterval))
    lastAngle = angle
    smoothedVelocity += (rawVelocity - smoothedVelocity) * 0.4
    player.update(velocityDegreesPerSecond: smoothedVelocity)
    if debug {
        print(String(format: "angle: %6.1f°  velocity: %+7.1f°/s  raw: %@",
                     angle, smoothedVelocity, sensor.rawReportHex()))
    }
}
RunLoop.main.add(timer, forMode: .common)
RunLoop.main.run()
