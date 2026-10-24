# Verification record

Executed on 13 October 2026 in the project environment:

- Created `.venv` and installed NumPy 2.0.2, sounddevice 0.5.6 and soundfile 0.13.1 (development interpreter: Apple silicon CPython 3.9.6; recommended user setup: Python 3.11+).
- `python3 -m unittest discover -s tests -v`: initial seven pure compensation tests passed.
- Syntax compilation of main.py, ui.py, audio_engine.py and compensation.py passed with a writable temporary bytecode-cache location. The initial default cache location was denied by the workspace sandbox; this was a cache-path issue, not a syntax failure.
- `.venv/bin/python -m unittest discover -s tests -v`: all 14 tests passed, including seven offline audio-engine tests.
- `.venv/bin/python -c 'import ui'`: Tkinter, UI and audio imports passed.

The audio tests invoke the callback directly on NumPy arrays, generate temporary WAV files and mock device opening. They verify stereo/mono processing, 50 ms smoothing, clipping, pause/cursor behaviour, stop/reset, EOF/restart, digital channel isolation, mono loading, multichannel rejection and sample-rate error reporting. They do not open a physical output or play sound.

Not performed: rendered GUI inspection, mouse interaction, actual stream/device playback, audible smoothing, speaker routing, macOS balance, disconnect behaviour on hardware, or measured room loudness. Follow the manual checklist in README.md for these checks.
