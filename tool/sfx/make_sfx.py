"""Synthesizes the game's sound effects (all original, made here from sine
waves and noise) into assets/sfx/*.wav.

    python3 tool/sfx/make_sfx.py   (from the project root)
"""
import os
import wave

import numpy as np

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'sfx')
rng = np.random.default_rng(7)


def t(sec):
    return np.arange(int(RATE * sec)) / RATE


def env(n, attack=0.005, decay=6.0):
    x = np.arange(n) / RATE
    a = np.clip(x / attack, 0, 1)
    return a * np.exp(-x * decay)


def tone(freq, sec, decay=6.0, wave_='sine', sweep=0.0):
    x = t(sec)
    f = freq * np.exp(sweep * x)
    ph = 2 * np.pi * np.cumsum(f) / RATE
    if wave_ == 'square':
        s = np.sign(np.sin(ph)) * 0.6
    elif wave_ == 'tri':
        s = 2 / np.pi * np.arcsin(np.sin(ph))
    else:
        s = np.sin(ph)
    return s * env(len(x), decay=decay)


def noise(sec, decay=20.0, lowpass=0.5):
    n = rng.uniform(-1, 1, int(RATE * sec))
    # one-pole low-pass for a softer burst
    y = np.zeros_like(n)
    for i in range(1, len(n)):
        y[i] = y[i - 1] + lowpass * (n[i] - y[i - 1])
    return y * env(len(n), decay=decay)


def seq(*parts, gap=0.0):
    out = []
    for p in parts:
        out.append(p)
        if gap:
            out.append(np.zeros(int(RATE * gap)))
    return np.concatenate(out)


def mix(*xs):
    n = max(len(x) for x in xs)
    return sum(np.pad(x, (0, n - len(x))) for x in xs)


def save(name, x, gain=0.8):
    x = x / (np.abs(x).max() + 1e-9) * gain
    data = (x * 32767).astype('<i2').tobytes()
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)


os.makedirs(OUT, exist_ok=True)
save('hit', mix(noise(0.12, 30, 0.6), tone(180, 0.12, 25, sweep=-4)), 0.7)
save('crit', mix(noise(0.18, 18, 0.8), tone(320, 0.18, 14, 'square', sweep=-3), tone(960, 0.1, 30)), 0.8)
save('hurt', mix(tone(110, 0.22, 12, 'tri', sweep=-2), noise(0.1, 35, 0.25)), 0.75)
save('whoosh', noise(0.18, 10, 0.15) * np.sin(np.linspace(0, np.pi, int(RATE * 0.18))), 0.45)
save('special', mix(seq(*[tone(f, 0.07, 14, 'square') for f in (523, 659, 784, 1047)]), noise(0.35, 6, 0.3) * 0.4), 0.6)
save('levelup', seq(*[tone(f, 0.09, 10, 'square') for f in (523, 659, 784)], tone(1047, 0.35, 5, 'square')), 0.4)
save('fight', mix(tone(196, 0.3, 6, 'square'), tone(294, 0.3, 6, 'square'), noise(0.12, 25, 0.5)), 0.5)
save('victory', seq(*[tone(f, 0.11, 8, 'square') for f in (523, 523, 659, 784)], tone(1047, 0.6, 3, 'square')), 0.4)
save('defeat', seq(*[tone(f, 0.18, 6, 'tri') for f in (392, 349, 311)], tone(262, 0.7, 2.5, 'tri')), 0.5)
save('tick', tone(1600, 0.03, 80, 'square'), 0.25)
save('pick', seq(tone(784, 0.06, 20, 'square'), tone(1175, 0.12, 14, 'square')), 0.35)
save('ability', mix(tone(220, 0.35, 5, 'tri', sweep=1.5), noise(0.3, 8, 0.2) * 0.5), 0.5)
print(sorted(os.listdir(OUT)))
