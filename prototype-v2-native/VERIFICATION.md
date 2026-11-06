# Verification — 29 October 2026

- Debug build: passed; all 11 automated tests passed.
- Release build: passed; all 11 automated tests passed.
- Standalone app: launched successfully on this Apple silicon Mac; local ad-hoc signature verified.
- Dashboard inspected in macOS dark appearance: speaker panel left, room centre, listener panel right, transport bottom. Side panels scroll to reach additional controls.
- UI four-speaker selector verified: rear calculations and planning-only labels appear; unavailable rear output controls are disabled.
- Listener x edited to 1.50 m in the running UI: distances, automatic gain and arrival delays updated immediately.
- A wrapped comparison label seen in the initial inspection was removed; Original and Processed remain explicitly named.

Automated tests exercise geometry, ear rotation, gain model, additive adjustments, arrival-time equality, stereo/four-speaker separation, mute/solo, head rotation, input constraints, delayed impulses, original channel integrity, pause, repeat/end, identification routing, and 44.1 kHz mono decoding/resampling.

Not established by these checks: real speaker routing, perceived loudness consistency, useful acoustic cancellation, listening quality during live movement, hardware output changes, and microphone-measured separation. These require the physical setup.

## Listening checklist

1. Set the Mac output to the AUX-connected system; confirm front-left and front-right Identify tones.
2. Enter measured room, speaker and listener geometry, including heights.
3. Use a familiar stereo file. Compare Original and Processed at a fixed position and level.
4. Test each processing switch separately at central, offset, near and far positions; record any gain limiting.
5. Rotate heading through 0°, 90°, 180° and 270° with ear separation enabled; assess stereo image and tonal changes.
6. Compare pause/resume, seek, stop, repeat and end-of-file behaviour. Listen for clicks or pitch shifts during delay movement.
7. Repeat with measured ear-level signals before drawing conclusions about headphone-like reproduction.

## Version 0.2.1 regression checks

Added tests for centre-line versus sideways alignment delay, rotation independent of ear cancellation, and actual rendered stereo swapping after a 180° turn. Live inspection of the installed original build at x=1, y=3 confirmed left added delay 2.94 ms and right 0.00 ms. The delay calculation was functioning; the presentation and rotation dependency needed correction.

Release 0.2.1: all 14 tests passed. The rendered-stereo test confirms that rotation changes the output samples with cancellation disabled.

## Version 0.3 — 1 November 2026

- Release build: all 17 tests passed, including the 14 legacy regressions.
- New forward-model check propagates the FIR outputs through all four ideal speaker/ear paths at 1 and 2 kHz, at headings 0, 30, 180 and 210 degrees. Required desired-ear amplitude >0.5, leakage ratio <0.35 forward/back and <0.65 oblique. These thresholds describe selected ideal-model cases, not broadband or real-room measurements.
- Sideways filters are finite and bounded; no claim of separation at that singular geometry.
- Rendered output samples agree with direct FIR calculations after smoothing; filter-history reset clears residual audio. The release rendering test processes 8192 frames plus verification in approximately 10 ms on this Mac.
- Ad-hoc package signature verified. Version 0.3 UI launched; Virtual headphones starts enabled, legacy switches disabled. Load ear check produces an 8-second track without autoplay. Changing direction to 90 degrees displays the limited-separation warning.
- Acoustic behaviour on the Z407 remains unverified. The user must enter measured geometry and physically match the diagram; the app does not track them. No in-ear measurements, head diffraction or room/speaker calibration have been implemented.

## Version 0.4 — 5 November 2026

Added microphone calibration and a dedicated Measurements page. Synthetic tests check relative level and timing with constant latency and linear clock drift, matched corrected signals, rejection of silence/clipping, and replacement of geometry corrections while preserving manual trims. Physical Yeti/AUX measurements still require the user's hardware; no acoustic performance is claimed from synthetic tests.
