"""Original military score for Fireteam Fury.

Composes MIDI with mido and renders it with FluidSynth + the FluidR3 GM
soundfont (MIT licence), so the brass, snare drums, timpani and strings are
real recorded instrument samples. Every melody here was written for this game.

    apt install fluidsynth fluid-soundfont-gm ffmpeg ; pip install mido
    python3 tools/make_score.py assets/music
"""
import os, subprocess, sys, wave
import numpy as np
import mido

SF2 = "/usr/share/sounds/sf2/FluidR3_GM.sf2"
SR = 44100
TPB = 480
NOTE = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def midi(n):
    p, o = (n[:2], n[2:]) if len(n) > 2 and n[1] in "#b" else (n[:1], n[1:])
    return NOTE[p] + (int(o) + 1) * 12


# GM programs / drum keys
TRUMPET, TROMBONE, TUBA, HORN, BRASS, STRINGS, CELLO, TIMPANI = 56, 57, 58, 60, 61, 48, 42, 47
KICK, SNARE, SIDE, CRASH, HAT, TOM_LO = 36, 38, 37, 49, 42, 45


class Song:
    def __init__(self, bpm):
        self.bpm = bpm
        self.ev = []  # (tick, channel, kind, a, b)
        self.programs = {}

    def prog(self, ch, program, vol=100, pan=64, reverb=40):
        self.programs[ch] = (program, vol, pan, reverb)

    def note(self, ch, beat, n, dur, vel=90):
        t0 = int(beat * TPB); t1 = int((beat + dur) * TPB)
        key = midi(n) if isinstance(n, str) else n
        self.ev.append((t0, 1, ch, key, vel))
        self.ev.append((max(t1 - 5, t0 + 1), 0, ch, key, 0))

    def line(self, ch, beat, notes, vel=90, legato=0.92):
        for n, d in notes:
            if n != "-":
                self.note(ch, beat, n, d * legato, vel)
            beat += d
        return beat

    def chord(self, ch, beat, ns, dur, vel=80):
        for n in ns:
            self.note(ch, beat, n, dur, vel)

    def drum(self, beat, key, vel):
        self.note(9, beat, key, 0.1, vel)

    def save(self, path):
        mf = mido.MidiFile(ticks_per_beat=TPB)
        tr = mido.MidiTrack(); mf.tracks.append(tr)
        tr.append(mido.MetaMessage("set_tempo", tempo=mido.bpm2tempo(self.bpm)))
        for ch, (p, vol, pan, rev) in self.programs.items():
            if ch != 9:
                tr.append(mido.Message("program_change", channel=ch, program=p))
            tr.append(mido.Message("control_change", channel=ch, control=7, value=vol))
            tr.append(mido.Message("control_change", channel=ch, control=10, value=pan))
            tr.append(mido.Message("control_change", channel=ch, control=91, value=rev))
        last = 0
        for t, on, ch, key, vel in sorted(self.ev, key=lambda e: (e[0], e[1])):
            msg = "note_on" if on else "note_off"
            tr.append(mido.Message(msg, channel=ch, note=key, velocity=vel, time=t - last))
            last = t
        mf.save(path)


# ------------------------------------------------------------------ drums
def cadence(s, beat, bars, base=1.0, roll_end=True):
    """Military snare cadence: accented 16ths, flams and a closing roll."""
    pat = [110, 0, 60, 70, 100, 0, 60, 0, 110, 0, 60, 70, 100, 55, 65, 75]
    for b in range(bars):
        last = roll_end and b == bars - 1
        for i, v in enumerate(pat):
            if last and i >= 8:
                break
            if v:
                s.drum(beat + b * 4 + i * 0.25, SNARE, int(min(127, v * base)))
        if last:  # 32nd-note roll crescendo into the next bar
            for k in range(16):
                s.drum(beat + b * 4 + 2 + k * 0.125, SNARE, int(min(127, (55 + k * 4) * base)))


def march_beat(s, beat, bars, crash_every=4):
    for b in range(bars):
        t = beat + b * 4
        s.drum(t, KICK, 100); s.drum(t + 2, KICK, 90)
        if b % crash_every == 0:
            s.drum(t, CRASH, 95)


def timp_roll(s, beat, n, beats, v0=50, v1=110):
    steps = int(beats * 6)
    for k in range(steps):
        s.note(5, beat + k / 6, n, 0.15, int(v0 + (v1 - v0) * k / max(steps - 1, 1)))


CHORDS = {
    "Dm": ["D3", "F3", "A3"], "Am": ["A2", "C3", "E3"], "Bb": ["Bb2", "D3", "F3"], "A": ["A2", "C#3", "E3"],
    "Gm": ["G2", "Bb2", "D3"], "F": ["F2", "A2", "C3"], "C": ["C3", "E3", "G3"], "Em": ["E2", "G2", "B2"],
    "D": ["D3", "F#3", "A3"], "G": ["G2", "B2", "D3"], "B": ["B2", "D#3", "F#3"],
}


def accompany(s, beat, chords, strings_8ths=True, vel=1.0):
    for i, c in enumerate(chords):
        t = beat + i * 4
        root = CHORDS[c][0]; fifth = CHORDS[c][2]
        r = midi(root) - 12
        # tuba + low strings: march root / fifth
        for q in range(4):
            n = r if q % 2 == 0 else midi(fifth) - 12
            s.note(3, t + q, n, 0.7, int(95 * vel))
        # trombones: off-beat chord stabs
        for q in (1, 3):
            s.chord(2, t + q, CHORDS[c], 0.45, int(78 * vel))
        # strings: driving 8th-note ostinato
        if strings_8ths:
            for e in range(8):
                n = midi(root) + (12 if e % 2 else 0)
                s.note(4, t + e * 0.5, n, 0.4, int((80 if e % 2 == 0 else 62) * vel))
        s.note(5, t, r + 12 if r + 12 <= midi("F3") else r, 0.9, int(100 * vel))  # timpani downbeat


# ------------------------------------------------------------------ pieces
def theme():
    s = Song(108)
    s.prog(0, TRUMPET, 110, 70, 50); s.prog(1, HORN, 105, 50, 60); s.prog(2, TROMBONE, 88, 80, 50)
    s.prog(3, TUBA, 105, 64, 40); s.prog(4, STRINGS, 80, 40, 60); s.prog(5, TIMPANI, 110, 64, 50)
    s.prog(9, 0, 105, 64, 35)
    A = [
        [("D5", 1.5), ("A4", .5), ("D5", .5), ("E5", .5), ("F5", 1)],
        [("E5", 1.5), ("C5", .5), ("A4", 2)],
        [("Bb4", 1), ("D5", .5), ("F5", .5), ("A5", 1.5), ("G5", .5)],
        [("F5", .5), ("E5", .5), ("D5", .5), ("E5", .5), ("A4", 2)],
        [("D5", 1.5), ("A4", .5), ("D5", .5), ("E5", .5), ("F5", 1)],
        [("G5", 1.5), ("F5", .5), ("E5", .5), ("F5", .5), ("G5", 1)],
        [("A5", 1), ("Bb5", .5), ("A5", .5), ("G5", .5), ("F5", .5), ("E5", 1)],
        [("D5", 3), ("-", 1)],
    ]
    A_ch = ["Dm", "Am", "Bb", "A", "Dm", "Gm", "A", "Dm"]
    B = [
        [("F5", 1.5), ("C5", .5), ("F5", 1), ("A5", 1)],
        [("G5", 1.5), ("F5", .5), ("E5", 1), ("C5", 1)],
        [("D5", 1.5), ("F5", .5), ("Bb5", 1), ("A5", 1)],
        [("A5", 3), ("-", 1)],
        [("Bb5", 1.5), ("A5", .5), ("G5", 1), ("F5", 1)],
        [("E5", 1.5), ("F5", .5), ("G5", 1), ("A5", 1)],
        [("D5", 1), ("F5", 1), ("E5", 1), ("C#5", 1)],
        [("D5", 2), ("A4", 1), ("A4", 1)],
    ]
    B_ch = ["F", "C", "Bb", "A", "Gm", "A", "A", "Dm"]
    beat = 0
    # intro: snare cadence alone, then timpani roll under it
    cadence(s, beat, 2, 0.95, roll_end=False)
    cadence(s, beat + 8, 2, 1.05)
    timp_roll(s, beat + 12, "A2", 4)
    beat = 16
    for sec, (mel, ch) in enumerate([(A, A_ch), (B, B_ch), (A, A_ch)]):
        for i in range(8):
            t = beat + i * 4
            s.line(0, t, mel[i], 100 if sec < 2 else 112)
            # horns double the tune an octave down, louder in the last section
            s.line(1, t, [(n if n == "-" else n[:-1] + str(int(n[-1]) - 1), d) for n, d in mel[i]], 90 if sec != 1 else 100)
        accompany(s, beat, ch, strings_8ths=True, vel=0.9 if sec == 0 else 1.0)
        cadence(s, beat, 8, 0.8)
        march_beat(s, beat, 8)
        beat += 32
    # tag: final chord with roll
    s.chord(0, beat, ["D5", "F5", "A5"], 3, 110); s.chord(1, beat, ["D4", "A4"], 3, 105)
    s.chord(2, beat, CHORDS["Dm"], 3, 100); s.note(3, beat, "D2", 3, 110)
    timp_roll(s, beat, "D3", 3, 90, 120); s.drum(beat, CRASH, 120); s.drum(beat, KICK, 120)
    return s, beat + 6, beat + 4  # (song, render beats, loop length in beats)


def mission():
    s = Song(132)
    s.prog(0, TRUMPET, 100, 76, 45); s.prog(1, HORN, 110, 48, 55); s.prog(2, TROMBONE, 90, 84, 45)
    s.prog(3, TUBA, 100, 64, 35); s.prog(4, STRINGS, 92, 36, 50); s.prog(5, TIMPANI, 105, 64, 45)
    s.prog(6, CELLO, 100, 54, 40); s.prog(9, 0, 110, 64, 30)
    horn = [
        [("E4", 2), ("B4", 1), ("G4", 1)], [("A4", 1.5), ("G4", .5), ("F#4", 2)],
        [("E4", 2), ("B4", 1), ("D5", 1)], [("C5", 1.5), ("B4", .5), ("A4", 1), ("B4", 1)],
        [("E5", 1.5), ("F#5", .5), ("G5", 1), ("B5", 1)], [("A5", 1.5), ("G5", .5), ("F#5", 2)],
        [("G5", 1), ("F#5", 1), ("E5", 1), ("D#5", 1)], [("E5", 3), ("-", 1)],
    ]
    ch = ["Em", "D", "Em", "C", "Em", "D", "C", "B"]
    loop = 64
    for rep in range(2):
        b0 = rep * 32
        for i in range(8):
            t = b0 + i * 4
            if i < 4:
                s.line(1, t, horn[i], 100 + rep * 10)
                if rep:
                    s.line(0, t, horn[i], 85)  # trumpets join the second time
            else:
                s.line(0, t, horn[i], 105 + rep * 8)
                s.line(1, t, [(n if n == "-" else n[:-1] + str(int(n[-1]) - 1), d) for n, d in horn[i]], 95)
            # cello/strings: relentless 16th ostinato on the root
            root = midi(CHORDS[ch[i]][0])
            for k in range(16):
                n = root + (7 if k % 4 == 3 else 0) + (12 if k % 8 >= 4 else 0)
                s.note(6, t + k * 0.25, n, 0.2, 92 if k % 4 == 0 else 70)
            s.note(3, t, root - 12, 1.8, 105); s.note(3, t + 2.5, root - 12, 1.2, 95)
            for q in (0, 1.5, 3):
                s.chord(2, t + q, CHORDS[ch[i]], 0.35, 92 if q == 0 else 80)
            s.chord(4, t, [root + 12, root + 19], 4, 60)
            s.note(5, t, root if root <= midi("F3") else root - 12, 0.5, 110)
            s.note(5, t + 2.5, root if root <= midi("F3") else root - 12, 0.5, 90)
        cadence(s, b0, 8, 0.9 + rep * 0.1)
        march_beat(s, b0, 8, 4)
        for i in range(8):  # driving kick 8ths on bars 5-8
            if i >= 4:
                for e in range(8):
                    s.drum(b0 + i * 4 + e * 0.5, KICK, 70)
    return s, loop + 2, loop


def win():
    s = Song(116)
    s.prog(0, TRUMPET, 115, 64, 60); s.prog(1, HORN, 110, 50, 60); s.prog(2, TROMBONE, 100, 80, 60)
    s.prog(3, TUBA, 100, 64, 50); s.prog(5, TIMPANI, 110, 64, 60); s.prog(9, 0, 110, 64, 50)
    for k in range(8):
        s.drum(k * 0.125, SNARE, 60 + k * 7)
    t = 1
    tri = 1 / 3
    s.line(0, t, [("D5", tri), ("D5", tri), ("D5", tri), ("A5", 1), ("F#5", .5), ("A5", .5), ("D6", 3)], 115)
    s.line(1, t, [("D4", tri), ("D4", tri), ("D4", tri), ("F#4", 1), ("D4", .5), ("F#4", .5), ("A4", 3)], 105)
    s.chord(2, t + 2, CHORDS["D"], 3, 105); s.note(3, t + 2, "D2", 3, 110)
    timp_roll(s, t + 2, "D3", 2.5, 80, 125)
    s.drum(t + 2, CRASH, 120); s.drum(t + 2, KICK, 120)
    return s, 7.5, None


def lose():
    s = Song(66)
    s.prog(0, TRUMPET, 100, 64, 80); s.prog(1, HORN, 100, 50, 80); s.prog(2, TROMBONE, 90, 80, 80)
    s.prog(5, TIMPANI, 100, 64, 70); s.prog(9, 0, 80, 64, 60)
    s.line(0, 0, [("A4", .75), ("D5", .25), ("F5", 1), ("E5", .5), ("C5", .5), ("D5", 2.5)], 92, legato=0.97)
    s.chord(1, 1, ["D4", "F4"], 1, 75); s.chord(1, 2, ["C4", "E4"], 1, 75); s.chord(1, 3, ["A3", "D4"], 2.5, 80)
    s.chord(2, 3, CHORDS["Dm"], 2.5, 75)
    timp_roll(s, 3, "D3", 2, 90, 40)
    for k in range(4):
        s.drum(k * 1.0, SIDE, 60)
    return s, 7.5, None


# ------------------------------------------------------------------ render
def render(song, beats, loop_beats, out, tmp):
    mid = tmp + ".mid"; wav = tmp + ".wav"
    song.save(mid)
    subprocess.run(["fluidsynth", "-ni", "-g", "0.45", "-r", str(SR), "-R", "1", "-C", "0",
                    "-F", wav, SF2, mid], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with wave.open(wav) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), np.int16).reshape(-1, 2).astype(np.float32) / 32768
    spb = 60 / song.bpm
    if loop_beats:
        n = int(loop_beats * spb * SR)
        tail = x[n:]
        x = x[:n].copy()
        m = min(len(tail), n)
        x[:m] += tail[:m]  # fold ringing tail into the start: seamless loop
    else:
        x = x[: int(beats * spb * SR)]
        fade = int(0.4 * SR)
        x[-fade:] *= np.linspace(1, 0, fade)[:, None]
    x /= max(np.abs(x).max(), 1e-6)
    x = np.tanh(x * 1.8) / np.tanh(1.8) * 0.92  # gentle compression so it carries on phone speakers
    with wave.open(wav, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", out], check=True)
    os.remove(wav); os.remove(mid)


if __name__ == "__main__":
    d = sys.argv[1]
    os.makedirs(d, exist_ok=True)
    for name, fn in [("theme", theme), ("mission", mission), ("win", win), ("lose", lose)]:
        song, beats, loop = fn()
        render(song, beats, loop, os.path.join(d, name + ".ogg"), os.path.join(d, "_" + name))
        print(name, "ok")
