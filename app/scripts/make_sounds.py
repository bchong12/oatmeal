"""Builds the pill's sounds: calm, rounded mallet tones instead of the system Tink and Pop.
Run: python3 scripts/make_sounds.py (writes Resources/Sounds/*.wav)."""
import math, struct, wave, os

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "Resources", "Sounds")

def note(freq, length, gain, decay):
    """A soft mallet: sine body with a quiet octave. Slow-ish attack so there's no click."""
    out = []
    for n in range(int(length * RATE)):
        t = n / RATE
        attack = min(1.0, t / 0.012)
        body = math.sin(2 * math.pi * freq * t) * math.exp(-t / decay)
        octave = 0.10 * math.sin(2 * math.pi * freq * 2 * t) * math.exp(-t / (decay * 0.4))
        out.append(gain * attack * (body + octave))
    return out

def render(name, notes, total):
    buf = [0.0] * int(total * RATE)
    for f, start, length, gain, decay in notes:
        s = int(start * RATE)
        for k, v in enumerate(note(f, length, gain, decay)):
            if s + k < len(buf): buf[s + k] += v
    fade = int(0.05 * RATE)
    for k in range(fade): buf[-1 - k] *= k / fade
    with wave.open(os.path.join(OUT, name), "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in buf))

A4, D5, E5 = 440.0, 587.33, 659.25
# Pops up: two low notes rising, a fourth apart.
render("pill-start.wav", [(A4, 0.0, 0.40, 0.22, 0.11), (E5, 0.08, 0.40, 0.18, 0.12)], 0.48)
# Done: the same two falling, settling on the lower one.
render("pill-stop.wav", [(E5, 0.0, 0.36, 0.18, 0.10), (A4, 0.08, 0.46, 0.22, 0.14)], 0.54)
# Cancelled: one soft note.
render("pill-cancel.wav", [(D5, 0.0, 0.32, 0.15, 0.09)], 0.34)
