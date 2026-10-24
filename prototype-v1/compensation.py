"""Pure relative free-field amplitude model; coordinates are metres."""
from dataclasses import dataclass
from math import hypot, isfinite


def distance(p, q):
    if not all(isfinite(v) for v in (*p, *q)):
        raise ValueError('Coordinates must be finite.')
    return max(hypot(p[0] - q[0], p[1] - q[1]), 0.25)


@dataclass(frozen=True)
class Compensation:
    distances: tuple
    requested: tuple
    gains: tuple
    limited: bool


def position_to_gains(listener, speakers, reference_distances, baseline=0.25):
    if len(speakers) != 2 or len(reference_distances) != 2:
        raise ValueError('Exactly two speakers and reference distances are required.')
    if not isfinite(baseline) or baseline < 0:
        raise ValueError('Baseline must be finite and nonnegative.')
    if any(not isfinite(d) or d < 0.25 for d in reference_distances):
        raise ValueError('Reference distances must be finite and at least 0.25 m.')
    ds = tuple(distance(listener, s) for s in speakers)
    requested = tuple(baseline * d / ref for d, ref in zip(ds, reference_distances))
    return Compensation(ds, requested, tuple(min(1., g) for g in requested),
                        any(g > 1 for g in requested))
