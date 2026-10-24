"""Offline callback checks: no stream opened, no physical audio produced."""
import math
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import numpy as np
import soundfile as sf
from audio_engine import AudioEngine


class AudioTests(unittest.TestCase):
    def setUp(self):
        self.engine = AudioEngine()
        self.engine.rate = 48000
        self.engine.decay = math.exp(-1 / 480)
        self.engine.data = np.tile(np.array([.5, -.25], dtype='float32'), (48000, 1))
        self.engine.mono = np.full((48000, 2), .125, dtype='float32')

    def block(self, frames=512):
        out = np.empty((frames, 2), dtype='float32')
        self.engine._callback(out, frames, None, None)
        return out

    def test_stereo_and_mono(self):
        self.engine.set_controls(.4, .8, .5, False, True)
        self.engine.current[:] = (.2, .4)
        np.testing.assert_allclose(self.block(), np.tile([.1, -.1], (512, 1)), atol=1e-6)
        self.engine.set_controls(.4, .8, .5, True, True)
        np.testing.assert_allclose(self.block(), np.tile([.025, .05], (512, 1)), atol=1e-6)

    def test_smoothing(self):
        self.engine.set_controls(1, 1, 1, False, True)
        out = self.block(2400)
        self.assertGreater(out[0, 0], 0)
        self.assertLess(out[0, 0], .002)
        self.assertTrue(np.all(np.diff(out[:, 0]) >= 0))
        self.assertAlmostEqual(float(self.engine.current[0]), 1-math.exp(-5), places=6)

    def test_pause_resume_stop_eof(self):
        self.engine.set_controls(.25, .25, .1, False, True)
        self.block()
        self.engine.pause()
        for _ in range(15):
            self.block()
        frozen = self.engine.cursor
        self.assertTrue(np.all(self.block() == 0))
        self.assertEqual(self.engine.cursor, frozen)
        with patch.object(self.engine, '_open'):
            self.engine.play(0)
        self.block()
        self.assertGreater(self.engine.cursor, frozen)
        self.engine.cursor = len(self.engine.data)-10
        out = self.block()
        self.assertTrue(np.all(out[10:] == 0))
        self.assertEqual(self.engine.report[0], 'Finished')
        self.assertTrue(np.all(self.block() == 0))
        with patch.object(self.engine, '_open'):
            self.engine.play(0)
        self.assertEqual(self.engine.cursor, 0)
        self.engine.stop()
        self.assertEqual(self.engine.cursor, 0)
        self.assertFalse(self.engine.controls[3])

    def test_clipping(self):
        self.engine.data[:] = (4, -4)
        self.engine.current[:] = 1
        self.engine.set_controls(1, 1, 1, False, True)
        out = self.block()
        self.assertTrue(self.engine.report[2])
        self.assertEqual(float(out.max()), 1)
        self.assertEqual(float(out.min()), -1)

    def test_channel_identification(self):
        for channel in (0, 1):
            with patch.object(self.engine, '_open'):
                self.engine.identify(0, channel)
            out = self.block(48000)
            self.assertTrue(np.all(out[:, 1-channel] == 0))
            self.assertGreater(float(np.abs(out[:, channel]).max()), .019)
            self.assertLessEqual(float(np.abs(out).max()), .020001)
            self.assertTrue(np.all(self.block() == 0))

    def test_load_mono_and_reject_multichannel(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'test.wav'
            sf.write(path, np.ones(100)*.1, 44100)
            self.engine.load(str(path))
            self.assertEqual(self.engine.data.shape, (100, 2))
            np.testing.assert_array_equal(self.engine.data[:, 0], self.engine.data[:, 1])
            sf.write(path, np.zeros((100, 3)), 44100)
            with self.assertRaises(ValueError):
                self.engine.load(str(path))

    def test_device_error(self):
        with patch('audio_engine.sd.check_output_settings', side_effect=RuntimeError('unsupported')):
            with self.assertRaisesRegex(RuntimeError, '44100 Hz'):
                self.engine._open(0, 44100)
        self.assertIsNone(self.engine.stream)
