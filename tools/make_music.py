"""Original soundtrack for Fireteam Fury, synthesised from scratch.

Writes assets/music/{theme,mission,win,lose}.ogg. Every melody here was
written for this game. Run:  python3 tools/make_music.py assets/music
"""
import os, subprocess, sys, wave
import numpy as np

SR = 44100
rng = np.random.default_rng(42)
NOTE = {n: i for i, n in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}


def hz(name):
    if name[1] in "#b":
        p, o = name[:2], int(name[2:])
    else:
        p, o = name[:1], int(name[1:])
    if p.endswith("b"):
        idx = NOTE[p[0]] - 1
    else:
        idx = NOTE[p]
    return 440.0 * 2 ** ((idx + (o + 1) * 12 - 69) / 12)


class Track:
    def __init__(self, seconds):
        self.buf = np.zeros((int(SR * seconds) + SR * 3, 2))

    def add(self, sig, t, pan=0.0, gain=1.0):
        i = int(t * SR)
        n = min(len(sig), len(self.buf) - i)
        if n <= 0:
            return
        l = np.cos((pan + 1) * np.pi / 4) * gain
        r = np.sin((pan + 1) * np.pi / 4) * gain
        self.buf[i:i + n, 0] += sig[:n] * l
        self.buf[i:i + n, 1] += sig[:n] * r


def env(n, a=0.01, d=0.1, s=0.7, r=0.08):
    t = np.arange(n) / SR
    dur = n / SR
    e = np.where(t < a, t / a, s + (1 - s) * np.exp(-(t - a) / max(d, 1e-3)))
    rel = np.clip((dur - t) / r, 0, 1)
    return e * rel


def brass(f, dur, bright=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.15) * 4, 0, 1)
    ph = 2 * np.pi * f * np.cumsum(vib) / SR
    # brightness swells on attack like a real horn
    br = np.clip(t / 0.06, 0, 1) * 0.7 + 0.3
    out = np.zeros(n)
    for k in range(1, 14):
        if f * k > 9000:
            break
        out += np.sin(k * ph) / k * np.exp(-k / (2.2 + 4.5 * br * bright))
    return out * env(n, 0.03, 0.25, 0.75, 0.06) * 0.6


def fife(f, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    vib = 1 + 0.008 * np.sin(2 * np.pi * 6.2 * t) * np.clip((t - 0.08) * 6, 0, 1)
    ph = 2 * np.pi * f * np.cumsum(vib) / SR
    breath = rng.standard_normal(n) * 0.04
    breath = np.convolve(breath, np.ones(8) / 8, "same")
    return (np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph) + breath) * env(n, 0.015, 0.08, 0.8, 0.03) * 0.5


def glock(f, dur=0.8):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 9) + 0.15 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t * 16)
    return s * np.exp(-t * 4.5) * np.clip(t * 800, 0, 1) * 0.35


def tuba(f, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    ph = 2 * np.pi * f * t
    s = sum(np.sin(k * ph) / k ** 1.4 for k in range(1, 8))
    return s * env(n, 0.012, 0.12, 0.55, 0.04) * 0.55


def pluck_bass(f, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    ph = 2 * np.pi * f * t
    s = np.sin(ph) + 0.5 * np.sin(2 * ph) * np.exp(-t * 8) + 0.25 * np.sin(3 * ph) * np.exp(-t * 14)
    return s * np.exp(-t * 3.5) * np.clip(t * 600, 0, 1) * 0.6


def noise_band(n, lo, hi):
    x = rng.standard_normal(n)
    X = np.fft.rfft(x)
    fr = np.fft.rfftfreq(n, 1 / SR)
    X[(fr < lo) | (fr > hi)] = 0
    return np.fft.irfft(X, n)


def snare(gain=1.0):
    n = int(0.22 * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 35)
    nz = noise_band(n, 1500, 9000) * np.exp(-t * 22)
    return (body * 0.5 + nz * 0.8) * gain * 0.55


def kick(gain=1.0):
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    f = 50 + 90 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9) * gain * 0.9


def hat(gain=1.0, open_=False):
    n = int((0.25 if open_ else 0.05) * SR)
    t = np.arange(n) / SR
    return noise_band(n, 7000, 16000) * np.exp(-t * (12 if open_ else 70)) * gain * 0.25


def crash(gain=1.0):
    n = int(2.2 * SR)
    t = np.arange(n) / SR
    return noise_band(n, 4000, 15000) * np.exp(-t * 2.2) * gain * 0.28


def roll(tr, t0, beats, beat, g0=0.25, g1=1.0):
    steps = int(beats * 8)
    for k in range(steps):
        g = g0 + (g1 - g0) * k / max(steps - 1, 1)
        tr.add(snare(g * 0.7), t0 + k * beat / 8, 0.15)


def reverb(buf, wet=0.18, length=1.6):
    n = int(length * SR)
    t = np.arange(n) / SR
    out = np.zeros_like(buf)
    for ch in range(2):
        ir = rng.standard_normal(n) * np.exp(-t * 4.0)
        ir[: int(0.02 * SR)] = 0
        L = len(buf) + n
        size = 1 << (L - 1).bit_length()
        y = np.fft.irfft(np.fft.rfft(buf[:, ch], size) * np.fft.rfft(ir, size), size)[: len(buf)]
        out[:, ch] = buf[:, ch] + y / np.sqrt((ir ** 2).sum()) * wet
    return out


def seq(tr, inst, notes, t0, beat, pan=0.0, gain=1.0, legato=0.92, **kw):
    t = t0
    for nt, b in notes:
        if nt != "-":
            tr.add(inst(hz(nt), b * beat * legato, **kw), t, pan, gain)
        t += b * beat
    return t


def write(tr, path, seconds, loop=True, wet=0.16):
    buf = reverb(tr.buf, wet)
    n = int(seconds * SR)
    if loop:
        # fold the reverb tail back onto the start so the loop is seamless
        tail = buf[n:]
        buf = buf[:n].copy()
        m = min(len(tail), n)
        buf[:m] += tail[:m]
    else:
        buf = buf[: n + SR]
    buf /= max(np.max(np.abs(buf)), 1e-6) / 0.89
    pcm = (buf * 32767).astype(np.int16)
    tmp = path + ".wav"
    with wave.open(tmp, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", "4", path], check=True)
    os.remove(tmp)


# ------------------------------------------------------------------ theme
def theme(out):
    bpm = 126; beat = 60 / bpm
    A = [
        [("D5", .5), ("F#5", .5), ("A5", 1), ("A5", .5), ("B5", .5), ("A5", 1)],
        [("G5", .5), ("F#5", .5), ("E5", 1), ("E5", .5), ("F#5", .5), ("G5", 1)],
        [("F#5", .5), ("E5", .5), ("D5", 1), ("D5", .5), ("E5", .5), ("F#5", 1)],
        [("E5", 1.5), ("D5", .5), ("E5", 2)],
        [("D5", .5), ("F#5", .5), ("A5", 1), ("A5", .5), ("B5", .5), ("A5", 1)],
        [("G5", .5), ("A5", .5), ("B5", 1), ("B5", .5), ("C#6", .5), ("D6", 1)],
        [("A5", .5), ("F#5", .5), ("G5", .5), ("E5", .5), ("F#5", 1), ("E5", 1)],
        [("D5", 2), ("-", 1), ("A4", 1)],
    ]
    A_ch = ["D", "A", "D", "A", "D", "G", "A", "D"]
    B = [
        [("B4", .5), ("D5", .5), ("G5", 1), ("G5", .5), ("F#5", .5), ("E5", 1)],
        [("F#5", .5), ("E5", .5), ("D5", 1), ("A4", 2)],
        [("B4", .5), ("D5", .5), ("G5", 1), ("B5", 1), ("A5", 1)],
        [("F#5", 3), ("-", 1)],
        [("E5", .5), ("F#5", .5), ("G5", .5), ("A5", .5), ("B5", 1), ("G5", 1)],
        [("A5", .5), ("B5", .5), ("A5", .5), ("G5", .5), ("F#5", 1), ("D5", 1)],
        [("E5", 1), ("F#5", 1), ("G5", 1), ("C#5", 1)],
        [("E5", 2), ("A4", 1), ("C#5", 1)],
    ]
    B_ch = ["G", "D", "G", "A", "E", "D", "A", "A"]
    roots = {"D": "D2", "A": "A1", "G": "G1", "E": "E2"}
    fifths = {"D": "A2", "A": "E2", "G": "D2", "E": "B2"}
    triads = {"D": ["F#4", "A4", "D5"], "A": ["E4", "A4", "C#5"], "G": ["G4", "B4", "D5"], "E": ["E4", "G4", "B4"]}
    intro = 2
    form = [("A", A, A_ch), ("B", B, B_ch), ("A", A, A_ch)]
    bars = intro + 8 * len(form)
    tr = Track(bars * 4 * beat)
    # intro: snare roll into a crash
    tr.add(kick(), 0); roll(tr, 0, 4, beat, 0.15, 0.6); roll(tr, 4 * beat, 4, beat, 0.6, 1.0)
    bar = intro
    for si, (name, mel, ch) in enumerate(form):
        for i in range(8):
            t0 = bar * 4 * beat
            if i == 0:
                tr.add(crash(), t0, -0.3)
            seq(tr, brass, mel[i], t0, beat, -0.1, 0.9)
            if si == 2:  # last A: glockenspiel doubles an octave up
                for nt, b in mel[i]:
                    pass
                t = t0
                for nt, b in mel[i]:
                    if nt != "-":
                        tr.add(glock(hz(nt) * 2), t, 0.45, 0.5)
                    t += b * beat
            c = ch[i]
            for b in range(4):
                tb = t0 + b * beat
                tr.add(tuba(hz(roots[c] if b % 2 == 0 else fifths[c]), beat * 0.5), tb, 0.0, 0.9)
                if b % 2 == 1:  # off-beat brass stabs
                    for k, nt in enumerate(triads[c]):
                        tr.add(brass(hz(nt) / 2 * 2, beat * 0.28, 0.6), tb, -0.5 + k * 0.5, 0.22)
                tr.add(kick(0.8 if b % 2 == 0 else 0.0), tb)
                tr.add(snare(0.35 if b % 2 == 0 else 0.8), tb, 0.15)
                tr.add(snare(0.25), tb + beat * 0.75, 0.15)
                tr.add(hat(0.7), tb + beat * 0.5, 0.35)
            if i == 7:
                roll(tr, t0 + 2 * beat, 2, beat, 0.2, 0.9)
            bar += 1
    write(tr, out, bars * 4 * beat)


# ------------------------------------------------------------------ mission loop
def mission(out):
    bpm = 138; beat = 60 / bpm
    M = [
        [("G5", .5), ("G5", .5), ("B5", .5), ("G5", .5), ("D6", 1), ("B5", 1)],
        [("C6", .5), ("B5", .5), ("A5", .5), ("G5", .5), ("A5", 1), ("E5", 1)],
        [("D5", .5), ("F#5", .5), ("A5", .5), ("F#5", .5), ("D6", 1), ("C6", 1)],
        [("B5", .5), ("A5", .5), ("G5", 1), ("G5", 1), ("-", 1)],
        [("E5", .5), ("G5", .5), ("B5", .5), ("E6", .5), ("D6", 1), ("B5", 1)],
        [("C6", .5), ("E6", .5), ("D6", .5), ("C6", .5), ("B5", 1), ("A5", 1)],
        [("A5", .5), ("B5", .5), ("C6", .5), ("A5", .5), ("F#5", 1), ("D5", 1)],
        [("G5", 1), ("D5", .5), ("B4", .5), ("G4", 1), ("-", 1)],
    ]
    ch = ["G", "C", "D", "G", "Em", "C", "D", "G"]
    bassline = {"G": ["G2", "B2", "D3", "B2"], "C": ["C3", "E3", "G3", "E3"], "D": ["D3", "F#3", "A3", "F#3"], "Em": ["E2", "G2", "B2", "G2"]}
    bars = 16
    tr = Track(bars * 4 * beat)
    for rep in range(2):
        for i in range(8):
            bar = rep * 8 + i
            t0 = bar * 4 * beat
            if i == 0:
                tr.add(crash(0.7), t0, 0.3)
            if rep == 0:
                seq(tr, fife, M[i], t0, beat, 0.2, 0.8, legato=0.8)
            else:
                seq(tr, brass, [(n[:-1] + str(int(n[-1]) - 1) if n != "-" else n, b) for n, b in M[i]], t0, beat, -0.2, 0.75, legato=0.85)
                seq(tr, fife, M[i], t0, beat, 0.3, 0.45, legato=0.8)
            for b in range(4):
                tb = t0 + b * beat
                tr.add(pluck_bass(hz(bassline[ch[i]][b]), beat * 0.9), tb, 0.0, 0.8)
                tr.add(kick(0.9 if b in (0, 2) else 0.3), tb)
                tr.add(snare(0.9 if b in (1, 3) else 0.2), tb, 0.1)
                tr.add(hat(0.6), tb + beat * 0.5, 0.4)
                tr.add(hat(0.35), tb, 0.4)
            if i == 3 or i == 7:
                roll(tr, t0 + 3 * beat, 1, beat, 0.3, 0.9)
    write(tr, out, bars * 4 * beat)


def win(out):
    beat = 60 / 120
    tr = Track(4)
    roll(tr, 0, 1, beat, 0.3, 1.0)
    t = beat
    for nt, b in [("G4", .33), ("C5", .33), ("E5", .34), ("G5", 1), ("E5", .5), ("G5", 2)]:
        tr.add(brass(hz(nt), b * beat * 0.95), t, 0, 1)
        tr.add(brass(hz(nt) * 0.75, b * beat * 0.95, 0.7), t, -0.4, 0.4)
        t += b * beat
    tr.add(crash(), beat * 3.0)
    tr.add(kick(), beat * 3.0)
    for nt in ["C3", "G3"]:
        tr.add(tuba(hz(nt), beat * 2), beat * 3.0, 0, 0.8)
    write(tr, out, 3.4, loop=False, wet=0.25)


def lose(out):
    beat = 60 / 90
    tr = Track(4)
    t = 0
    for i, nt in enumerate(["G4", "F#4", "F4", "E4"]):
        d = beat * (0.7 if i < 3 else 2.2)
        sig = brass(hz(nt), d * 0.95, 0.5)
        if i == 3:  # wobbling slide on the last note
            n = len(sig)
            tt = np.arange(n) / SR
            f = hz(nt) * (1 - 0.04 * tt) * (1 + 0.02 * np.sin(2 * np.pi * 5 * tt))
            ph = 2 * np.pi * np.cumsum(f) / SR
            sig = sum(np.sin(k * ph) / k * np.exp(-k / 3) for k in range(1, 10)) * env(n, 0.03, 0.4, 0.7, 0.3) * 0.6
        tr.add(sig, t)
        t += d
    write(tr, out, t + 0.3, loop=False, wet=0.25)


if __name__ == "__main__":
    d = sys.argv[1]
    os.makedirs(d, exist_ok=True)
    theme(os.path.join(d, "theme.ogg"))
    mission(os.path.join(d, "mission.ogg"))
    win(os.path.join(d, "win.ogg"))
    lose(os.path.join(d, "lose.ogg"))
    print("ok")
