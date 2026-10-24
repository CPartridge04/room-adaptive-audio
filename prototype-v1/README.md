# Two-speaker room-adaptive audio prototype

A local Python/Tkinter experiment for a Mac with Apple silicon and a stereo speaker output. No server, microphone, camera, tracking, equalisation or delay compensation. Start with the physical speaker volume low: the app starts at master gain **0.10**, compensation gains **0.25**, and never starts playback automatically.

## Mac setup

Install a standard, GIL-enabled Python 3.11 or newer using the macOS universal2 installer from [python.org](https://www.python.org/downloads/macos/). The [official installer includes Tk](https://www.python.org/download/mac/tcltk/). Do not use a free-threaded build: this prototype uses atomic Python object-reference assignment for controls and status.

Open folder in VsCode, then run:
/Users/carlpartridge/Audio/.venv-new/bin/python /Users/carlpartridge/Audio/main.py

1. Open VS Code
2. Choose file -> Open Folder -> /Users/carlpartridge/AudioAudio/prototype-v1
3. Open main.py
4. Press Cmd+Shift+P and choose Python: Run Pyhthon File in Terminal

## Alternatively

Open Terminal in this project directory, then run:

```sh
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
python -m tkinter
python main.py
```

The Tkinter command should open a small test window; close it before launching the app. Tkinter is part of the Python installation, not a pip dependency. If its import fails, install the python.org build and recreate the virtual environment with that interpreter. NumPy, sounddevice and soundfile are the only third-party Python dependencies. Their macOS wheels normally supply the necessary native audio libraries. If installation falls back to building native libraries, check that you are using a supported Python version and current pip.

## Choosing and checking your output

1. Connect the Logitech system. For an analogue cable, select the Mac headphone/external-headphones output or the USB audio adapter carrying that cable. Analogue Logitech speakers usually do not appear under the Logitech name. USB speakers may appear under their own name.
2. In macOS System Settings → Sound → Output, select that output and **centre the balance control**. Start with low macOS and speaker hardware volume. Turn off any mono-audio accessibility setting that would merge channels.
3. In the app, select the matching device. Only outputs reporting at least two channels are listed. The app uses the first two output channels; multichannel interfaces may need routing in their own control panel. Changing device or refreshing stops and resets playback.
4. Press **Test left**, then **Test right**. Each plays a one-second 440 Hz tone in just that digital channel, with a 50 ms fade at each end. The other channel is exactly zero. Tests use a fixed 0.02 peak amplitude (about −34 dBFS), bypass the app's master/branch gains, and reset file playback. Hardware volume still matters. Test output is checked at 48 kHz; if unsupported, the app gives an error.
5. Load a mono or stereo WAV and press Play. File sample rate and stereo output support are checked before opening playback. There is no resampler. If rejected, convert the WAV to a rate supported by the device, or choose another output. WAV files are loaded entirely into memory; use short files initially. Multichannel and non-WAV files are rejected.

A Logitech system with a shared subwoofer still receives two digital channels. Its internal crossover decides what reaches the subwoofer: this app cannot address it as a third speaker. A channel test can therefore sound from the selected satellite and the shared subwoofer.

## Controls

- **Original stereo:** preserves left and right source channels. A mono WAV is duplicated to both channels.
- **Mono test:** computes `(left + right) / 2` and duplicates it. Opposite-polarity stereo content can cancel when averaged.
- **Position compensation:** computes and caps each gain independently; manual sliders are disabled.
- **Manual:** independent gains from 0 to 1. Master volume multiplies both, in either mode.
- Click or drag inside the room to move the listener. Coordinates are metres, with origin at the top left, x to the right and y down. The drawing maintains equal scale on both axes.
- Edit width, depth and speaker coordinates, then Apply metres. Dimensions must be positive and finite; speakers must be in the room. The listener is clamped inside a resized room.
- **Set current position as reference:** stores the two current clamped distances. Both compensation gains immediately become 0.25. Editing room/speaker geometry preserves those stored distances until you explicitly set a new reference. They remain visible in the readout.
- **Pause:** fades down and then freezes the cursor. Up to roughly 0.12 seconds of audio is consumed during the quiet fade tail. Resume fades up from that position.
- **Stop:** closes the stream and resets to zero. It is an immediate stop, so an arbitrary waveform may produce a short discontinuity. Play after end-of-file restarts at zero. End-of-file outputs silence without looping; a source that ends away from zero can itself click.
- Clipping and audio stream warnings persist until Stop, a new file, a device change or a test. Device-open errors appear in a dialog. If a device disconnects, stop and reconnect it, then refresh and select it again.
- Pause before switching Original stereo / Mono test; source-mode switches are block-boundary changes without a crossfade.

## Maths

Let listener position be `p = (x, y)` and the two speaker positions be `q_L`, `q_R`:

```text
d_i(p) = max(sqrt((x − q_ix)² + (y − q_iy)²), 0.25 m)
h_i(p) = k_i / d_i(p), with k_L = k_R = 1
```

`h_i(p)` is a simplified **relative acoustic amplitude transfer** from one speaker's electrical drive to the listener. It is not calibrated sound pressure. The inverse-distance law models spreading of sound amplitude in an ideal free field. It is not an inverse-square amplitude law; squared amplitude/intensity falls approximately as inverse distance squared.

Initially `p_ref = (2, 2)`, `q_L = (1, 0.5)`, `q_R = (3, 0.5)`. Both reference distances are `sqrt(3.25) ≈ 1.8028 m`. With `g_ref = 0.25`:

```text
g_i,requested(p) = 0.25 × d_i(p) / d_i,ref
g_i(p) = min(1, max(0, g_i,requested(p)))
```

At the reference position the distance ratio is one. Before the cap:

```text
g_i(p) h_i(p) = (0.25 d_i(p) / d_i,ref) (k_i / d_i(p))
               = 0.25 k_i / d_i,ref
```

The distance cancels. Moving farther away requests more drive; moving closer requests less. This is constant modelled amplitude **for each branch and a fixed master volume**, not a constant waveform over time. The music still has its original dynamics. The 0.25 m minimum avoids singularities and makes a small region around each speaker have constant model distance.

For example, at `(1, 2)`, left distance is 1.5 m and right distance is 2.5 m, giving gains approximately 0.2080 and 0.3467. At `(3, 2)` the gains swap. If a requested gain exceeds 1, the display explicitly reports that the target cannot be maintained. The other channel is not silently renormalised. A requested gain of exactly 1 is feasible.

The pure function is in `compensation.py`. It knows nothing about audio, Tkinter or hardware, so future controllers can replace it independently.

## Signal path and smoothing

```text
WAV → soundfile decode to in-memory float32 samples
    → preserve stereo / average to dual mono
    → per-channel gain × master, smoothed
    → clip to [−1, +1] and latch a warning if necessary
    → sounddevice / PortAudio → selected stereo device
    → DAC/amplifier → Logitech speakers → room → listener
```

At steady state:

```text
output_left[n]  = master × g_L × source_left[n]
output_right[n] = master × g_R × source_right[n]
```

The effective channel gain `a = master × g_i` is smoothed with a one-pole recurrence:

```text
alpha = exp(−1 / (sample_rate × 0.010 seconds))
a[n] = target + alpha × (a[n−1] − target)
```

After 50 ms, the remaining error is `exp(−5) ≈ 0.0067`, so the change is 99.3% complete. This prevents jumps when dragging, changing master volume or changing branch gain. It briefly lags the ideal spatial model while you move.

The callback processes 512-frame blocks, with no file I/O, GUI calls, waiting or locks. It uses bounded NumPy calculations; Python and its small temporary arrays are suitable for a prototype but are not a hard real-time guarantee. The UI publishes one immutable control tuple and polls one immutable status tuple every 100 ms. The callback owns the cursor and current smoothed gains while running. File/device/test replacements close the stream first, so the callback cannot access partially replaced data. Files are decoded before starting playback. See the [sounddevice stream API](https://python-sounddevice.readthedocs.io/en/latest/api/streams.html) and [device checks](https://python-sounddevice.readthedocs.io/en/latest/api/checking-hardware.html).

## What this model cannot promise

The aim is approximately steady perceived loudness across positions. The model neglects reflections, directivity, frequency response, propagation delay and interference. Equal branch amplitudes do not ensure equal measured or perceived loudness. Identical mono signals are coherent and can reinforce or cancel according to path-length differences and frequency. Stereo content has changing correlation. Reflected sound and the shared subwoofer add further complexity. Listener hearing and frequency-dependent loudness perception also matter. There is no microphone validation in this version.

Later, `H_i(s, p)` can represent a measured linear transfer function from each output channel to a microphone at position `p`, including magnitude and phase versus frequency. Measure each channel separately using a known excitation and estimate its impulse response `h_i(t, p)`; a transform gives a frequency response `H_i(jω, p)`, or a fitted dynamic model gives `H_i(s, p)`. The two-speaker pressure model becomes `Y(s,p) = H_L(s,p) U_L(s) + H_R(s,p) U_R(s)`. Here lowercase impulse-response `h_i(t,p)` is distinct from this version's scalar `h_i(p)`.

Measured responses could later support band-limited loudness estimation and carefully constrained filters. An inverse is not automatically stable or robust: deep cancellations, non-minimum-phase behaviour, position variation and limited headroom need regularisation and gain limits. Measurement, delay alignment, equalisation and tracking are future work, not implemented here.

## Verification

Run the focused maths tests with:

```sh
python -m unittest discover -s tests -v
```

Hardware/manual checklist (perform on your device)

1. On launch, verify silence and master 0.10. At `(2,2)`, both gains should read 0.250.
2. Move down away from both speakers: both gains rise. Move towards a speaker: its gain falls. Compare symmetric positions `(1,2)` and `(3,2)`.
3. Click on a speaker: its displayed distance remains at least 0.250 m; no division-by-zero error occurs.
4. To force the limit visibly, set width/depth to 20, keeping speaker coordinates unchanged, then move to the opposite corner. Check the orange warning, requested gains above 1 and applied gains capped at 1. Reset the reference there: both become 0.250. Restore the original geometry and reference afterward.
5. Run both identification tests and confirm their physical satellite routing. A shared subwoofer may respond to either.
6. Play a short WAV. Drag slowly and rapidly, change manual gains and master: hear gradual changes without gain-step clicks. Verify a stereo file retains channel differences, and mono mode duplicates its average.
7. Pause, wait, and verify the time freezes after its short fade. Resume, then Stop and verify zero time. Play again from the beginning. Let the file end: status Finished, silence, and Play restarts.
8. Try an invalid file and unsupported sample rate/device combination: expect a clear dialog. Close the window during playback: output should cease and the stream close.
9. To check clipping, use a floating-point WAV whose samples exceed ±1, set manual gains and master to 1 at very low hardware volume, and confirm the clipping warning. Ordinary PCM WAV at gains ≤1 should not clip.

Automated checks run in the development environment are recorded in `VERIFICATION.md`. Listening, physical routing and end-to-end GUI/device behaviour remain manual checks; they cannot be certified by maths tests.
