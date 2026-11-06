## Version 0.4 — microphone calibration and Measurements page

Use the new Calibrate page with Blue Yeti selected as macOS default input and headphone/AUX as default output. Place the microphone at your listening position, use omnidirectional mode, and leave hardware volume and microphone gain fixed. The app requests microphone access only when you start a measurement.

Measure speakers records a continuous left–right–left sequence of 120 ms, 600–6000 Hz sweeps. Correlation locates the strongest matching arrival. The repeated left event brackets the right event to cancel constant device latency and approximately cancel linear clock drift. This is relative timing, not absolute acoustic travel time. Strong reflections can bias the estimate. Level is RMS over the detected sweep, in dBFS; it is not calibrated SPL or a full-band loudness measurement. This version does not equalize frequency response or independently calibrate the subwoofer.

Apply automatic corrections attenuates the louder speaker and delays the earlier one. It replaces geometry gain/timing, disables virtual headphones and channel mixing, and preserves manual trims. Verify corrections records the same sequence with final gain and delay applied. Mute/solo affect verification. Original playback bypasses corrections. Re-measure when the setup changes and verify after editing manual trims.

Measurements shows the recorded waveform, arrival markers, three measured levels and timestamps, before/after relative differences, and current automatic/manual/final settings. Play or export the latest recording as WAV. Recordings and settings are session-only; export before quitting. Missing signals, clipped recordings, weak signals, inconsistent repeated levels, and extreme mismatches are rejected. Device changes cancel a test.

Build output: `prototype-v2-native/dist/Audio Lab.app` within this project. The earlier documentation below describes previous versions.

## Version 0.3 — manual virtual headphones

The app now starts in **Virtual headphones (experimental)** mode. Enter measured speaker positions and your real ear-centre position, height, ear spacing and direction. Physically match the diagram; there is no head tracking. Use Processed, load music and play. **Load ear check** replaces the loaded track with an eight-second alternating test (700 Hz left ear, 1100 Hz right ear); press Play to hear it. It does not start playback automatically.

This mode uses a regularized inverse of the four free-field speaker-to-ear paths, not the old stereo panner. A 512-tap, 48 kHz FIR matrix includes 5.33 ms latency, smooth filter transitions and per-speaker path compensation. The inverse is regularized (lambda 0.04) to limit amplification at poorly conditioned frequencies and angles. Manual trims, mute/solo and master still apply; changing individual trims or silencing an output compromises separation. The legacy processing switches are disabled while this mode supplies its own gain and timing. Original bypasses it.

This is an **unmeasured geometric approximation**: no head diffraction, individual HRTFs, room reflections, speaker response or shared subwoofer model. It does not promise headphone equivalence. Separation varies strongly with frequency and angle, especially sideways; the app displays an angle warning. Exact position matters. A physical listening or ear-microphone test is required to validate results on the Z407. The lower-frequency subwoofer signal is not independently controllable per ear.

The earlier documentation below describes the legacy mode, available by turning Virtual headphones off.

# Audio — Spatial Listening Lab

A standalone native SwiftUI Mac prototype for manual listening experiments. Open **Audio Lab.app** from the downloaded release or build it locally. The app follows macOS light/dark appearance, starts silent, and requires no Python environment or server. Built for Apple silicon, macOS 13 or later.

## First listening session

1. Connect the Logitech Z407 via AUX. In macOS Sound settings choose the headphone output or stereo adapter connected to it. Centre the system balance.
2. Enter room dimensions and speaker/listener positions. Coordinates start at the top-left; x increases right and y increases down. 0° faces the top. Heights do not change when dragging.
3. Use each front speaker’s **Identify** button to check routing. This pauses music without resetting its position and plays a quiet 0.8-second tone in that output. Hardware volume still determines actual loudness.
4. Load a mono/stereo music file (WAV, AIFF, CAF, MP3, AAC and other formats supported by macOS). Files are decoded in memory and resampled to 48 kHz. The prototype limit is 15 minutes. Unsupported/protected files report an error.
5. Press Play. Drag the listener, speakers, or arrow handle, or use numeric fields. Compare the independent processing switches. Original/Processed crossfades while preserving the timeline. Original bypasses all spatial processing, speaker gain/delay trims, mute and solo; master still applies.
6. Pause freezes position. Stop returns to zero. Seek with the timeline; Repeat loops. The final delayed audio tail can play for up to 200 ms after the timeline reaches the end.

## Controls and defaults

The example room is 4 × 5 m, listener at (2,3), height 1.2 m, ear spacing 0.18 m, heading 0°. Speakers start 0.4 m from the corners at height 1.2 m. Distance gain and timing alignment start enabled; head-relative stereo starts enabled; ear separation starts disabled. Master starts at 0.15 (−16.5 dB).

Four-speaker mode is a **planning mode**. All four distances, ear paths, gains and delays are calculated and drawn. The front pair continues to play over stereo. Its playback delay is calculated against the front pair and shown separately from four-speaker planned delay. Rear mute/solo/Identify are unavailable because there are no independent rear outputs in this version. Connecting a multichannel interface does not enable four-output audio in this prototype.

Manual gain (−24 to +12 dB) and manual additional delay (0–100 ms) are independent, additive and separately resettable. Automatic values are zero when their switch is disabled, leaving manual values active in Processed mode. Final gain is capped at −60 to +18 dB; final delay at 0–200 ms. A cap warning appears on the card. The chart uses cyan for gain, orange for delay; output meters show digital peak amplitude, not acoustic loudness.

## Processing model

For speaker distance `d = max(0.1, sqrt(dx²+dy²+dz²))`:

- Automatic gain: `20 log10(d / 2 m)` dB. This compensates ideal free-field amplitude loss relative to a fixed 2 m distance, avoiding changing the reference as the listener moves.
- Automatic delay: `(max(active distances) − d) / 343` seconds. Adding acoustic propagation time gives equal centre-of-head arrival time.
- Final gain/delay: automatic plus manual, subject to the displayed caps.
- Ear positions rotate about the listener using the entered ear spacing. The independent Head-relative stereo switch uses head-relative equal-power stereo weights, normalised across the two actual outputs. Ear separation optionally subtracts a weak opposite-channel term, with strength `0.35 × nearEarDistance/farEarDistance` and delay `abs(leftEarDistance−rightEarDistance)/343`.

This last model is deliberately experimental. It is **not** a measured transfer-matrix inverse, HRTF renderer, or validated crosstalk canceller. Two fixed speakers cannot reproduce arbitrary headphone signals at every position and orientation. Side-facing geometry can collapse the stereo image. Reflections, shared subwoofer output, speaker directivity and frequency response are not modelled. Constant calculated amplitude does not guarantee constant perceived loudness. Listening and microphone measurements must establish effectiveness.

Parameters and the comparison blend are smoothed. Delay changes use a moving fractional read position and can cause temporary pitch shifts. Pause/Stop are immediate and may click at a waveform discontinuity; resume/seek use a short fade-in. Repeat is sample-continuous for a compatible source loop but does not crossfade arbitrary file ends. A final ±0.98 peak clamp prevents digital overflow; its latched warning means the master or trims should be reduced, since limiting alters the experiment.

## Implementation and verification

Native SwiftUI UI and AVAudioEngine with a stereo AVAudioSourceNode. Uses the current Mac default output. Output changes pause playback and ask the listener to check routing and resume. No recording, tracking, setup saving, audio capture, microphone calibration or network access.

File decoding occurs off the UI thread. The audio callback does no file I/O and never waits for a lock: if the shared state is briefly unavailable, that block is silent and the cursor does not advance. This is a pragmatic prototype, not a production hard-real-time audio engine. The UI publishes settings and polls meter/transport state at 20 Hz.

Build and run tests from this directory with `swift test`. Build a standalone app with `./build-app.sh`. Xcode command-line tools are required for rebuilding, not for running the app. The local app is ad-hoc signed, not notarised for distribution.

Tests cover three-dimensional geometry, ear rotation, arrival-time equality, additive trims, inverse-distance gain, four-speaker/stereo separation, mute/solo, channel rotation, constraints, impulse delay, original channel integrity, paused cursor, repeat/end behaviour, identification routing and mono-file resampling. See VERIFICATION.md for recorded results and listening checks.

Apple framework reference: https://developer.apple.com/documentation/avfaudio/performing-offline-audio-processing

## Version 0.2.1 — rotation and timing clarity

Head-relative stereo now operates independently of experimental ear separation and starts enabled. Each front card shows its left/right input amplitude weights (not percentages of power). Original still bypasses processing. Use a stereo file with distinct left/right content when comparing 0° and 180°; identical mono channels cannot demonstrate a left/right swap.

Speaker cards distinguish acoustic sound-travel time from added alignment delay. On the centre line, both speakers have equal travel times and require zero added delay. At the default geometry, listener x=1 m, y=3 m gives the left speaker approximately 2.94 ms added delay, with zero on the right. The delay chart now scales to the current values so small changes are visible. Head rotation affects channel weights and ear paths; it does not change centre-of-head alignment delay.
