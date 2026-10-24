# Room-Adaptive Audio

**Work in progress — by Carl Partridge**

An audio engineering project exploring how speaker output can adapt to listener position.

## Current prototype

The first prototype uses two speakers, a Python/Tkinter interface, WAV playback, and position-based channel gains calculated from a simplified inverse-distance model.

It includes manual gain controls, channel identification tones, gain smoothing, and offline tests.

This is an initial model-based experiment. Constant perceived loudness in a real room has not been established. Listener tracking, microphone measurements, equalisation, and delay compensation are future work.

See [prototype setup and technical documentation](prototype-v1/README.md).

## Preserved prototype

The `prototype-v1` branch and `v0.1.0-prototype` tag preserve the first public prototype. Ongoing project development will appear on `main`.

This repository contains selected public milestones from a separate local development repository.
