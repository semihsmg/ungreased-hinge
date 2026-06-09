# ungreased-hinge

> WD-40 in reverse.

Makes your MacBook lid creak like an old door when you open or close it. Every MacBook ships with a hinge-angle sensor; this tool reads it 60 times a second and plays a rusty creak whenever the lid is moving. When the lid stops, the creak pauses mid-squeak and resumes from the same spot on the next move — just like a real neglected hinge.

## Requirements

- A MacBook with a lid-angle sensor (Apple Silicon models have one)
- macOS 14+
- Xcode command line tools (`xcode-select --install`)

## Install

```sh
git clone https://github.com/semihsmg/ungreased-hinge.git
cd ungreased-hinge
./install.sh
```

This builds `UngreasedHinge.app` and drops it into `/Applications`.

**Open the app to start creaking. Open it again to stop.** There's no window, no Dock icon, no menu bar item — the only user interface is the hinge itself.

## Run from the terminal instead

```sh
swift run -c release UngreasedHinge          # ctrl-c to quit
swift run -c release UngreasedHinge --debug  # prints live angle + velocity
```

Running it a second time stops the first instance, same as the app.

## How it works

- The lid-angle sensor is a HID device (Apple SPU, usage page `0x20` "Sensor", usage `0x8A` "Orientation: Hinge Angle"). Feature report #1 returns the angle in degrees: `0` closed, ~`128` fully open.
- `LidAngleSensor.swift` polls it at 60 Hz via IOKit and computes a smoothed angular velocity.
- `CreakPlayer.swift` loops a creak recording through `AVAudioEngine`, playing while the lid moves (above 3°/s) and pausing in place when it stops.

## Tuning

- Movement sensitivity: `movementThreshold` in `CreakPlayer.swift`
- The sound itself: replace `Sources/UngreasedHinge/Resources/creak.wav` and rerun `./install.sh`

## Known limitation

Closing the lid past ~10° puts the Mac to sleep, so the final inch of the close is silent. Physics: 1, comedy: 0.

## Credits

The creak recording (`CREAK_LOOP.wav`) comes from [samhenrigold/LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) (MIT), which pioneered the lid-as-instrument genre.
