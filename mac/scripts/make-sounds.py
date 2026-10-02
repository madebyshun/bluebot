#!/usr/bin/env python3
"""BlueBot's sounds, synthesised from scratch (no samples, no third-party audio).

Coucou's sounds are not MIT (see LICENSE-COUCOU / Coucou's LICENSE-ASSETS.md),
so BlueBot ships its own: short, soft, glassy tones in a Blue Agent register.
Re-run to regenerate:  python3 scripts/make-sounds.py   (from mac/)
Writes Resources/sounds/<name>.wav — mono, 44.1 kHz, 16-bit.
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "Resources", "sounds")


def note(name):
    """'E5' → Hz."""
    names = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((names[pitch] + (octave - 4) * 12) / 12)


def tone(freq, dur, amp=0.7, attack=0.004, decay=None, glide_to=None, bright=0.18):
    """A bell-ish tone: sine + a soft octave partial, fast attack, exponential decay."""
    n = int(dur * RATE)
    decay = decay or dur / 4.5
    out = []
    phase = phase2 = 0.0
    for i in range(n):
        t = i / RATE
        f = freq if glide_to is None else freq + (glide_to - freq) * (i / n)
        phase += 2 * math.pi * f / RATE
        phase2 += 2 * math.pi * f * 2 / RATE
        env = min(1.0, t / attack) * math.exp(-t / decay)
        out.append(amp * env * (math.sin(phase) + bright * math.sin(phase2)) / (1 + bright))
    return out


def noise(dur, amp=0.5, decay=0.02):
    rnd = random.Random(7)
    return [amp * math.exp(-(i / RATE) / decay) * (rnd.random() * 2 - 1) for i in range(int(dur * RATE))]


def seq(*parts, gap=0.0):
    """Notes one after another, each allowed to ring under the next."""
    total = []
    offset = 0
    for p in parts:
        need = offset + len(p)
        if len(total) < need:
            total += [0.0] * (need - len(total))
        for i, v in enumerate(p):
            total[offset + i] += v
        offset += int(len(p) * 0.45) + int(gap * RATE)
    return total


def write(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = min(1.0, 0.85 / peak)
    tail = [0.0] * int(0.01 * RATE)
    frames = b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples + tail)
    with wave.open(os.path.join(OUT, f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)


SOUNDS = {
    # island opens / closes
    "open":    lambda: seq(tone(note("E5"), 0.14), tone(note("B5"), 0.2)),
    "close":   lambda: seq(tone(note("B5"), 0.12, amp=0.55), tone(note("E5"), 0.18, amp=0.55)),
    "peek":    lambda: tone(note("B5"), 0.09, amp=0.4),
    "hover":   lambda: tone(note("E6"), 0.05, amp=0.25, bright=0.05),
    # small UI acknowledgements
    "blip":    lambda: tone(note("A5"), 0.07, amp=0.45),
    "pop":     lambda: tone(note("G5"), 0.09, glide_to=note("C5"), amp=0.6, bright=0.05),
    "approve": lambda: seq(tone(note("G5"), 0.1), tone(note("D6"), 0.16)),
    # events
    "finish":  lambda: seq(tone(note("C6"), 0.16), tone(note("E6"), 0.16), tone(note("G6"), 0.3)),   # an alert fired
    "error":   lambda: seq(tone(note("E4"), 0.16, bright=0.35), tone(note("C4"), 0.26, bright=0.35)),  # a BLOCK / failure
    "love":    lambda: seq(tone(note("E5"), 0.12), tone(note("G#5"), 0.12), tone(note("B5"), 0.12), tone(note("E6"), 0.32)),  # linked
    "greet":   lambda: seq(tone(note("B5"), 0.14, amp=0.55), tone(note("E6"), 0.24, amp=0.55)),
    # the character being poked
    "annoyed": lambda: seq(tone(note("D4"), 0.09, bright=0.6), tone(note("C#4"), 0.14, bright=0.6)),
    "slap":    lambda: [a + b for a, b in zip(noise(0.08, amp=0.6), tone(note("A3"), 0.08, amp=0.4) + [0.0] * 10)],
}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, make in SOUNDS.items():
        write(name, make())
    print(f"wrote {len(SOUNDS)} sounds to {os.path.normpath(OUT)}")
