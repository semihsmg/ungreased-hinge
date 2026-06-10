import AVFoundation

/// Plays a creaky-hinge loop at its natural speed whenever the lid is moving,
/// and pauses in place when it stops — each movement resumes the recording
/// from where the last squeak left off.
final class CreakPlayer {
    /// Lid speed (deg/s) below which the lid counts as still.
    static let movementThreshold = 3.0

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let buffer: AVAudioPCMBuffer
    private var currentVolume: Float = 0
    private var needsRestart = false
    private var suspended = false

    init() throws {
        guard let url = Bundle.module.url(forResource: "creak", withExtension: "wav") else {
            throw NSError(domain: "UngreasedHinge", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "creak.wav missing from bundle"])
        }
        let file = try AVAudioFile(forReading: url)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                               frameCapacity: AVAudioFrameCount(file.length)) else {
            throw NSError(domain: "UngreasedHinge", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "could not allocate audio buffer"])
        }
        try file.read(into: pcmBuffer)
        buffer = pcmBuffer

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
        player.volume = 0

        // Output device changes (sleep/wake, headphones) stop the engine; restart it.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.restart()
        }

        try start()
    }

    private func start() throws {
        try engine.start()
        player.scheduleBuffer(buffer, at: nil, options: .loops)
    }

    /// While the system is sleeping or waking, CoreAudio tears down the output
    /// device, and touching the player mid-transition makes AVFoundation raise
    /// an NSException that Swift cannot catch (it crashed the app on two
    /// sleep/wake cycles). So: hands off the engine entirely from the moment
    /// sleep is announced until after wake.
    func suspend() {
        suspended = true
        player.stop()
        engine.stop()
    }

    func resume() {
        suspended = false
        // Rebuild lazily on the next movement; immediate restarts can still
        // catch CoreAudio before the output device is back.
        needsRestart = true
    }

    // player.stop() discards the scheduled loop, and CoreAudio can refuse to
    // start for a few seconds right after wake — so a failure here must be
    // remembered and retried from update(), or the player stays silent with
    // nothing scheduled.
    private func restart() {
        guard !suspended else { return }
        player.stop()
        do {
            try start()
            needsRestart = false
        } catch {
            needsRestart = true
        }
    }

    func update(velocityDegreesPerSecond: Double) {
        guard !suspended else { return }
        let moving = abs(velocityDegreesPerSecond) > Self.movementThreshold
        // Short attack/release ramp so starting and stopping doesn't click.
        let targetVolume: Float = moving ? 1 : 0
        let smoothing: Float = targetVolume > currentVolume ? 0.5 : 0.25
        currentVolume += (targetVolume - currentVolume) * smoothing
        player.volume = currentVolume

        // Pause the whole engine while silent so its render thread isn't
        // burning CPU mixing silence; restarting takes only a few ms, hidden
        // behind the attack ramp.
        if currentVolume > 0.01 {
            if needsRestart { restart() }
            if !engine.isRunning { try? engine.start() }
            if engine.isRunning, !player.isPlaying { player.play() }
        } else {
            if player.isPlaying { player.pause() }
            if engine.isRunning { engine.pause() }
        }
    }
}
