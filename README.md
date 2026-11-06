# Room Adaptive Audio

An experimental audio lab for comparing stereo speaker processing and measuring speakers at a listening position.

## Native Mac app — v0.4.0

The SwiftUI app in [`prototype-v2-native`](prototype-v2-native) includes:

- A room layout with speaker and listener positions.
- Microphone calibration to match relative speaker level and arrival time.
- Separate manual gain and delay trims.
- A Measurements dashboard with a recorded waveform, arrival markers, measured levels, before/after differences, and applied corrections.
- Recording playback and WAV export.

### Setup

Designed for Logitech Z407 speakers connected through AUX and a Blue Yeti connected through USB. Select the headphone/AUX output and Yeti input in macOS Sound settings. Place the microphone at the listening position, choose omnidirectional mode, and keep hardware volume and microphone gain fixed.

On the **Calibrate** page, choose **Measure speakers → Apply automatic corrections → Verify corrections**. Microphone permission is requested when starting a measurement. The test uses a left–right–left sweep sequence. Results and settings currently last for the app session; export recordings before closing.

Measurements are relative, not calibrated sound-pressure readings. Timing estimates can be affected by reflections. Physical Yeti/Z407 testing is still pending; automated checks use simulated recordings. Virtual headphones remains an experimental, unmeasured geometric model.

### Build

Requires Apple silicon, macOS 13 or later, and Xcode command-line tools.

```sh
cd prototype-v2-native
swift test
zsh build-app.sh
```

The app is created in `dist/Audio Lab.app`. Local builds are ad-hoc signed, not notarised for distribution.

## Original Python prototype

The original implementation remains in [`prototype-v1`](prototype-v1). See its README for setup instructions.
