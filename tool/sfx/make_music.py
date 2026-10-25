"""Composes the adventure's two music loops (original, synthesized here)
into assets/sfx/music_*.ogg.

    python3 tool/sfx/make_music.py   (from the project root; needs ffmpeg)

music_camp: the adventure home. Calm, warm, 92 BPM in C major.
music_battle: a run. Driving, 132 BPM in A minor.
Each loop's tail is folded back onto its start so it repeats without a seam.
"""
import os
import subprocess
import tempfile
import wave

import numpy as np
from scipy.signal import lfilter

RATE = 32000
OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'sfx')
rng = np.random.default_rng(11)

NOTES = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def hz(name):
    """'A4' → 440, 'C#5', 'Bb3'."""
    n = NOTES[name[0]]
    rest = name[1:]
    if rest[0] == '#':
        n, rest = n + 1, rest[1:]
    elif rest[0] == 'b':
        n, rest = n - 1, rest[1:]
    return 440.0 * 2 ** ((n - 9) / 12 + int(rest) - 4)


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / RATE)
    return lfilter([1 - a], [1, -a], x)


def adsr(n, a=0.01, d=0.1, s=0.7, r=0.1):
    x = np.arange(n) / RATE
    dur = n / RATE
    e = np.where(x < a, x / a, s + (1 - s) * np.exp(-(x - a) / max(d, 1e-4)))
    rel = np.clip((dur - x) / r, 0, 1)
    return e * rel


class Track:
    def __init__(self, bpm, bars):
        self.beat = 60 / bpm
        self.length = int(RATE * self.beat * 4 * bars)
        self.buf = np.zeros(self.length + RATE * 3)

    def at(self, beat):
        return int(round(beat * self.beat * RATE))

    def add(self, beat, sound, gain=1.0):
        i = self.at(beat)
        self.buf[i:i + len(sound)] += sound * gain

    def render(self):
        # Fold the tail onto the start: the loop point is seamless.
        out = self.buf[:self.length].copy()
        tail = self.buf[self.length:]
        out[:len(tail)] += tail
        return out


# Instruments ---------------------------------------------------------------

def pluck(f, sec=1.2, bright=1.0):
    """Kalimba / music-box: sine with a soft octave and a quick decay."""
    x = np.arange(int(RATE * sec)) / RATE
    s = np.sin(2 * np.pi * f * x) + 0.35 * bright * np.sin(2 * np.pi * 2 * f * x) * np.exp(-x * 9)
    s += 0.12 * bright * np.sin(2 * np.pi * 3.01 * f * x) * np.exp(-x * 14)
    return s * np.minimum(x / 0.004, 1) * np.exp(-x * 3.2)


def pad(freqs, sec):
    """Soft detuned saw chord, low-passed, slow in and out."""
    x = np.arange(int(RATE * sec)) / RATE
    s = np.zeros_like(x)
    for f in freqs:
        for det in (-0.12, 0.0, 0.12):
            ph = (f * 2 ** (det / 12) * x + rng.random()) % 1
            s += 2 * ph - 1
    s = lowpass(lowpass(s, 900), 1400) / (len(freqs) * 3)
    return s * adsr(len(x), a=0.35, d=0.6, s=0.8, r=0.4)


def soft_bass(f, sec):
    x = np.arange(int(RATE * sec)) / RATE
    s = np.sin(2 * np.pi * f * x) + 0.25 * np.sin(2 * np.pi * 2 * f * x)
    return s * adsr(len(x), a=0.01, d=0.25, s=0.6, r=0.08)


def pulse_bass(f, sec):
    x = np.arange(int(RATE * sec)) / RATE
    s = np.sign(np.sin(2 * np.pi * f * x)) * 0.5 + np.sin(2 * np.pi * f * x) * 0.6
    return lowpass(s, 700) * adsr(len(x), a=0.004, d=0.08, s=0.5, r=0.03)


def lead(f, sec):
    """Square-ish lead with a little vibrato, for the battle hook."""
    x = np.arange(int(RATE * sec)) / RATE
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * x) * np.minimum(x / 0.2, 1)
    ph = 2 * np.pi * np.cumsum(f * vib) / RATE
    s = 0.6 * np.sign(np.sin(ph)) + 0.5 * np.sin(ph)
    return lowpass(s, 2600) * adsr(len(x), a=0.008, d=0.15, s=0.65, r=0.06)


def kick():
    x = np.arange(int(RATE * 0.35)) / RATE
    f = 45 + 110 * np.exp(-x * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-x * 9)


def snare():
    x = np.arange(int(RATE * 0.22)) / RATE
    n = lowpass(rng.uniform(-1, 1, len(x)), 5000) - lowpass(rng.uniform(-1, 1, len(x)), 600) * 0.5
    return (0.7 * n * np.exp(-x * 18) + 0.4 * np.sin(2 * np.pi * 190 * x) * np.exp(-x * 25))


def hat(open_=False):
    x = np.arange(int(RATE * (0.15 if open_ else 0.05))) / RATE
    n = rng.uniform(-1, 1, len(x))
    n = n - lowpass(n, 6000)
    return n * np.exp(-x * (25 if open_ else 80))


def shaker():
    x = np.arange(int(RATE * 0.07)) / RATE
    n = rng.uniform(-1, 1, len(x))
    n = n - lowpass(n, 4000)
    return n * np.minimum(x / 0.01, 1) * np.exp(-x * 50)


# Songs ---------------------------------------------------------------------

def camp():
    t = Track(bpm=92, bars=8)
    chords = [('C3', ['C4', 'E4', 'G4']), ('A2', ['A3', 'C4', 'E4']),
              ('F2', ['F3', 'A3', 'C4']), ('G2', ['G3', 'B3', 'D4'])] * 2
    for bar, (root, tones) in enumerate(chords):
        b = bar * 4
        t.add(b, pad([hz(n) for n in tones], t.beat * 4.3), 0.33)
        t.add(b, soft_bass(hz(root), t.beat * 1.8), 0.32)
        t.add(b + 2, soft_bass(hz(root), t.beat * 1.5), 0.24)
        for e in range(8):
            t.add(b + e / 2, shaker(), 0.05 if e % 2 else 0.03)
        # Broken chord under the tune.
        for k, n in enumerate([tones[0], tones[1], tones[2], tones[1]]):
            t.add(b + k, pluck(hz(n) * 2, 1.0, 0.5), 0.10)
    # The tune (beat, note, beats), C major pentatonic.
    tune = [
        (0, 'E5', 1), (1, 'G5', 1), (2, 'A5', 1.5), (3.5, 'G5', .5),
        (4, 'E5', 1), (5, 'D5', 1), (6, 'C5', 2),
        (8, 'C5', 1), (9, 'D5', 1), (10, 'E5', 1), (11, 'G5', 1),
        (12, 'D5', 3),
        (16, 'E5', 1), (17, 'G5', 1), (18, 'A5', 1), (19, 'C6', 1),
        (20, 'A5', 1), (21, 'G5', 1), (22, 'E5', 2),
        (24, 'D5', 1), (25, 'E5', 1), (26, 'G5', 1), (27, 'E5', .5), (27.5, 'D5', .5),
        (28, 'C5', 3),
    ]
    for beat, n, length in tune:
        t.add(beat, pluck(hz(n), max(1.0, length * t.beat + 0.6)), 0.30)
    out = t.render()
    return out


def battle():
    t = Track(bpm=132, bars=16)
    prog = [('A1', ['A3', 'C4', 'E4']), ('F1', ['F3', 'A3', 'C4']),
            ('C2', ['C4', 'E4', 'G4']), ('G1', ['G3', 'B3', 'D4']),
            ('A1', ['A3', 'C4', 'E4']), ('F1', ['F3', 'A3', 'C4']),
            ('G1', ['G3', 'B3', 'D4']), ('E1', ['E3', 'G#3', 'B3'])] * 2
    for bar, (root, tones) in enumerate(prog):
        b = bar * 4
        intro = bar < 2
        # Drums: kick on 1 and 3 (plus a push), snare on 2 and 4, eighth hats.
        for k in (0, 2, 2.5) if not intro else (0, 2):
            t.add(b + k, kick(), 0.55)
        if not intro:
            t.add(b + 1, snare(), 0.32)
            t.add(b + 3, snare(), 0.32)
        for e in range(8):
            t.add(b + e / 2, hat(open_=(e == 7)), 0.10 if e % 2 else 0.06)
        if bar % 8 == 7:
            for k in (3.25, 3.5, 3.75):
                t.add(b + k, snare(), 0.18)
        # Eighth-note bass.
        for e in range(8):
            f = hz(root) * (2 if e in (3, 7) else 1)
            t.add(b + e / 2, pulse_bass(f, t.beat * 0.45), 0.30)
        # Sixteenth arpeggio.
        arp = [tones[0], tones[1], tones[2], tones[1]]
        for s in range(16):
            t.add(b + s / 4, pluck(hz(arp[s % 4]) * 2, 0.25, 0.8), 0.07)
        t.add(b, pad([hz(n) for n in tones], t.beat * 4.2), 0.16)
    # The hook, in the second half.
    hook = [
        (0, 'E5', .75), (.75, 'E5', .75), (1.5, 'D5', .5), (2, 'C5', 1), (3, 'D5', 1),
        (4, 'E5', 1.5), (5.5, 'G5', .5), (6, 'A5', 2),
        (8, 'G5', .75), (8.75, 'E5', .75), (9.5, 'D5', .5), (10, 'C5', 1), (11, 'D5', 1),
        (12, 'B4', 2), (14, 'G#4', 2),
        (16, 'E5', .75), (16.75, 'E5', .75), (17.5, 'D5', .5), (18, 'C5', 1), (19, 'E5', 1),
        (20, 'G5', 1.5), (21.5, 'A5', .5), (22, 'C6', 2),
        (24, 'B5', 1), (25, 'A5', 1), (26, 'G5', 1), (27, 'E5', 1),
        (28, 'E5', 2), (30, 'G#5', 1), (31, 'B5', 1),
    ]
    for beat, n, length in hook:
        t.add(32 + beat, lead(hz(n), length * t.beat * 0.95), 0.14)
    return t.render()


def save(name, x):
    x = x / np.max(np.abs(x)) * 0.85
    x = np.tanh(x * 1.1) / np.tanh(1.1)
    pcm = (x * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
        tmp = f.name
    with wave.open(tmp, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    path = os.path.join(OUT, f'{name}.ogg')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', tmp, '-c:a', 'libvorbis', '-q:a', '4', path],
                   check=True)
    os.remove(tmp)
    print(path, f'{len(x) / RATE:.1f}s', f'{os.path.getsize(path) // 1024} KB')


if __name__ == '__main__':
    save('music_camp', camp())
    save('music_battle', battle())
