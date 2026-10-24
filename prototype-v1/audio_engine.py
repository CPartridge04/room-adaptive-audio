"""In-memory playback. UI publishes immutable controls; callback owns cursor.

Use standard GIL-enabled CPython. No locks, file reads, or Tk calls in callback.
Structural changes happen only after closing the stream (which joins callback).
"""
import math
import numpy as np
import sounddevice as sd
import soundfile as sf


class AudioEngine:
    def __init__(self):
        self.stream = None
        self.data = self.mono = None
        self.rate = 0
        self.cursor = 0
        self.controls = (0.025, 0.025, False, False)  # L, R, mono, playing
        self.current = np.zeros(2, dtype=np.float32)
        self.report = ('Stopped', 0, False, '')
        self.clipped = False
        self.diagnostic = ''
        self.test_data = None
        self.test_cursor = 0

    @staticmethod
    def devices():
        return [(i, d['name']) for i, d in enumerate(sd.query_devices())
                if d['max_output_channels'] >= 2]

    def close(self):
        if self.stream is not None:
            try:
                self.stream.close()
            finally:
                self.stream = None

    def load(self, path):
        with sf.SoundFile(path) as f:
            if f.format not in ('WAV', 'WAVEX', 'RF64'):
                raise ValueError('Please choose a WAV file.')
            if f.channels not in (1, 2):
                raise ValueError('Use a mono or stereo WAV; multichannel files are unsupported.')
            data = f.read(dtype='float32', always_2d=True)
            rate = f.samplerate
        if not len(data) or not np.isfinite(data).all():
            raise ValueError('WAV is empty or contains non-finite samples.')
        if data.shape[1] == 1: # type: ignore
            data = np.repeat(data, 2, axis=1)
        mono = np.repeat(data.mean(axis=1, keepdims=True, dtype=np.float64), 2, axis=1).astype('float32')
        self.stop()
        self.data, self.mono, self.rate = data, mono, rate

    def set_controls(self, left, right, master, mono, playing=None):
        values = (left, right, master)
        if any(not math.isfinite(v) or not 0 <= v <= 1 for v in values):
            raise ValueError('Gains must be between zero and one.')
        active = self.controls[3] if playing is None else playing
        self.controls = (left * master, right * master, bool(mono), bool(active))

    def _open(self, device, rate):
        try:
            sd.check_output_settings(device=device, channels=2, dtype='float32', samplerate=rate)
            self.decay = math.exp(-1 / (0.010 * rate))  # 99.3% settled in 50 ms
            self.stream = sd.OutputStream(device=device, samplerate=rate, channels=2,
                                          dtype='float32', blocksize=512, callback=self._callback)
            self.stream.start()
        except Exception as exc:
            self.close()
            raise RuntimeError(f'Cannot open stereo output at {rate} Hz. Select another device or convert the WAV sample rate.\n{exc}') from exc

    def play(self, device):
        if self.data is None:
            raise ValueError('Load a WAV file first.')
        if self.stream is not None and not self.stream.active:
            self.close()
        if self.test_data is not None:
            self.stop()
        if self.cursor >= len(self.data):
            self.close()
            self.cursor = 0
            self.current[:] = 0
        if self.stream is None:
            self._open(device, self.rate)
        l, r, mono, _ = self.controls
        self.controls = (l, r, mono, True)

    def status(self):
        if self.stream is not None and not self.stream.active:
            state, cursor, clipped, diagnostic = self.report
            return ('Audio error', cursor, clipped,
                    diagnostic or 'Output stopped unexpectedly; stop, refresh and select the device again.')
        return self.report

    def pause(self):
        l, r, mono, _ = self.controls
        self.controls = (l, r, mono, False)

    def stop(self):
        self.close()
        self.pause()
        self.cursor = self.test_cursor = 0
        self.test_data = None
        self.current[:] = 0
        self.clipped = False
        self.diagnostic = ''
        self.report = ('Stopped', 0, False, '')

    def identify(self, device, channel):
        self.stop()
        rate = 48000
        t = np.arange(rate) / rate
        envelope = np.minimum(1, np.minimum(t / .05, (1 - t) / .05))
        self.test_data = np.zeros((rate, 2), dtype='float32')
        self.test_data[:, channel] = .02 * np.sin(2 * np.pi * 440 * t) * envelope
        self._open(device, rate)

    def _callback(self, outdata, frames, time_info, status):
        outdata.fill(0)
        try:
            if status:
                self.diagnostic = str(status)
            if self.test_data is not None:
                n = min(frames, len(self.test_data) - self.test_cursor)
                outdata[:n] = self.test_data[self.test_cursor:self.test_cursor + n]
                self.test_cursor += n
                state = 'Channel test' if n and self.test_cursor < len(self.test_data) else 'Test finished'
            elif self.data is not None:
                l, r, mono, playing = self.controls
                target = np.array((l, r) if playing else (0., 0.), dtype='float32')
                ramp = target + (self.current - target) * np.power(self.decay, np.arange(1, frames + 1))[:, None]
                self.current[:] = ramp[-1]
                n = min(frames, len(self.data) - self.cursor)
                if playing or np.max(self.current) > 1e-6:
                    source = self.mono if mono else self.data
                    outdata[:n] = source[self.cursor:self.cursor + n] * ramp[:n] # type: ignore
                    self.cursor += n
                state = 'Finished' if self.cursor >= len(self.data) else ('Playing' if playing else 'Paused')
            else:
                state = 'Stopped'
            if np.any(np.abs(outdata) > 1):
                self.clipped = True
            np.clip(outdata, -1, 1, out=outdata)
            self.report = (state, self.cursor, self.clipped, self.diagnostic)
        except Exception:
            outdata.fill(0)
            self.report = ('Audio error', self.cursor, self.clipped, 'Callback failed; stop and reopen the output.')
            raise sd.CallbackAbort
