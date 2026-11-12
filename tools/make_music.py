"""Synthesises the game's music and a few extra sounds. Original work, released CC0 with the game.

Acoustic timbres only (producer: no electronic sounds): a lute (plucked strings, additive
synthesis with stiff-string partials), a recorder, frame drums, a shaker and a church bell, in a
small stone room. Every run makes identical files (fixed seed).

    python tools/make_music.py            # everything
    python tools/make_music.py menu night # only these pieces

Needs numpy, scipy and ffmpeg. Output: assets/music/*.ogg, assets/audio/{bell,ui_tick,ui_tock}.ogg
The battle music is three loops of the same length that play together (music_player.gd raises
them one by one as the day goes on): battle_lute, battle_drums, battle_tune.
"""
import pathlib, subprocess, sys, wave
import numpy as np
from scipy.signal import butter, fftconvolve, sosfilt

SR = 44100
ROOT = pathlib.Path(__file__).resolve().parent.parent
rng = np.random.default_rng(1215)

SEMITONE = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def hz(name: str) -> float:
    """'D4', 'Bb3', 'F#5' -> frequency (A4 = 440)."""
    return 440.0 * 2 ** ((SEMITONE[name[:-1]] + 12 * (int(name[-1]) + 1) - 69) / 12)


def band(x, low=None, high=None, order=2):
    if low and high:
        sos = butter(order, [low, high], btype="band", fs=SR, output="sos")
    elif low:
        sos = butter(order, low, btype="high", fs=SR, output="sos")
    else:
        sos = butter(order, high, btype="low", fs=SR, output="sos")
    return sosfilt(sos, x, axis=0)


# ---- instruments (mono) -----------------------------------------------------------------------
_cache = {}


def pluck(freq: float, ring: float, bright: float = 1.0) -> np.ndarray:
    """One lute course: two gut strings a few cents apart, plucked near the bridge."""
    key = ("pluck", round(freq, 2), round(ring, 2), bright)
    if key in _cache:
        return _cache[key]
    n = int(SR * ring)
    t = np.arange(n) / SR
    out = np.zeros(n)
    tau1 = 1.9 * (220.0 / freq) ** 0.35  # low strings ring longer
    for detune, delay in ((1.0012, 0.0), (0.9988, 0.007)):
        f0 = freq * detune
        shifted = np.maximum(t - delay, 0.0)
        for k in range(1, int(min(36, 6500 / f0)) + 1):
            fk = k * f0 * np.sqrt(1 + 0.00012 * k * k)  # stiffness: upper partials run sharp
            amp = np.sin(np.pi * k * 0.17) / k ** (1.3 - 0.25 * bright)  # plucked at 17% of the string
            tau = tau1 / (1 + 0.016 * k * k / bright)
            out += amp * np.exp(-shifted / tau) * np.sin(2 * np.pi * fk * shifted)
    # Finger noise on the attack, then the string speaks.
    attack = int(0.006 * SR)
    out[:attack] += band(rng.standard_normal(attack), 1500, 5000) * 0.25 * np.linspace(1, 0, attack)
    out *= np.minimum(t / 0.0015, 1.0)
    out[-int(0.03 * SR):] *= np.linspace(1, 0, int(0.03 * SR))
    # A lute's small body gives little below its air resonance: thin out the lowest octave.
    out = 0.42 * out + 0.58 * band(out, low=150, order=1)
    out *= 0.5
    _cache[key] = out
    return out


def recorder(freq: float, dur: float, vib: float = 1.0) -> np.ndarray:
    """A wooden recorder: soft attack with a little chiff, breath in the tone, late vibrato."""
    key = ("recorder", round(freq, 2), round(dur, 3), vib)
    if key in _cache:
        return _cache[key]
    n = int(SR * (dur + 0.13))
    t = np.arange(n) / SR
    wobble = 0.0042 * vib * np.clip((t - 0.16) / 0.3, 0, 1) * np.sin(2 * np.pi * 5.3 * t)
    drift = 0.0012 * np.sin(2 * np.pi * 0.7 * t + freq)  # breath pressure is never perfectly steady
    phase = 2 * np.pi * freq * np.cumsum(1 + wobble + drift) / SR
    tone = np.sin(phase) + 0.30 * np.sin(2 * phase + 0.5) + 0.13 * np.sin(3 * phase + 1.1) + 0.045 * np.sin(4 * phase) + 0.02 * np.sin(5 * phase)
    env = np.minimum(t / 0.05, 1.0) * np.clip((dur + 0.11 - t) / 0.11, 0, 1)
    env *= 0.85 + 0.15 * np.exp(-t / 0.22)
    breath = band(rng.standard_normal(n), 1500, 6500) * (0.022 + 0.11 * np.exp(-t / 0.035))
    out = (tone * 0.36 + breath) * env
    _cache[key] = out
    return out


def drum(kind: str) -> np.ndarray:
    """Frame-drum strokes: dum (centre), tak (rim), war (a big tabor), shake (seed rattle)."""
    key = ("drum", kind)
    if key in _cache:
        return _cache[key]
    if kind in ("dum", "war"):
        low, dur, decay = (66.0, 1.0, 0.3) if kind == "war" else (84.0, 0.7, 0.2)
        n = int(SR * dur)
        t = np.arange(n) / SR
        f = low + low * 0.75 * np.exp(-t / 0.022)  # the skin's pitch drops as it settles
        phase = 2 * np.pi * np.cumsum(f) / SR
        out = np.sin(phase) * np.exp(-t / decay)
        out += 0.35 * np.sin(1.59 * phase + 0.3) * np.exp(-t / (decay * 0.45))  # first drum mode above the fundamental
        out += 0.2 * np.sin(2.14 * phase + 0.8) * np.exp(-t / (decay * 0.3))
        slap = band(rng.standard_normal(n), 250, 2600) * np.exp(-t / 0.012)
        out = out * 0.9 + slap * (0.5 if kind == "war" else 0.35)
    elif kind == "tak":
        n = int(SR * 0.25)
        t = np.arange(n) / SR
        out = band(rng.standard_normal(n), 700, 3800) * np.exp(-t / 0.028) * 0.8
        out += 0.5 * np.sin(2 * np.pi * 330 * t) * np.exp(-t / 0.04)
        out += 0.3 * np.sin(2 * np.pi * 517 * t + 0.4) * np.exp(-t / 0.03)
    else:  # shake
        n = int(SR * 0.16)
        t = np.arange(n) / SR
        out = band(rng.standard_normal(n), 5200, 11000) * (np.exp(-t / 0.02) + 0.35 * np.exp(-((t - 0.035) / 0.012) ** 2)) * 0.5
    out[-200:] *= np.linspace(1, 0, 200)
    _cache[key] = out
    return out


def bell(freq: float = 196.0, dur: float = 6.0) -> np.ndarray:
    """A cast church bell: hum, prime, tierce, quint, nominal and the partials above them."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, amp, tau in ((0.5, 0.55, 5.0), (1.0, 1.0, 3.6), (1.19, 0.75, 2.6), (1.5, 0.4, 2.0), (2.0, 0.85, 1.7), (2.51, 0.35, 1.2), (3.01, 0.3, 0.9), (4.17, 0.22, 0.55), (5.43, 0.15, 0.35), (6.8, 0.1, 0.22)):
        out += amp * np.exp(-t / tau) * np.sin(2 * np.pi * freq * ratio * t + ratio)
    out += band(rng.standard_normal(n), 900, 5000) * np.exp(-t / 0.01) * 0.6  # the clapper
    out *= np.minimum(t / 0.002, 1.0)
    out[-2000:] *= np.linspace(1, 0, 2000)
    return out * 0.3


# ---- mixing -----------------------------------------------------------------------------------
def room(seconds: float = 1.7, seed: int = 7) -> np.ndarray:
    """Impulse response of a small stone hall: decaying noise, darker than the dry sound."""
    n = int(SR * seconds)
    t = np.arange(n) / SR
    ir = np.random.default_rng(seed).standard_normal((n, 2)) * np.exp(-t / (seconds / 6.9))[:, None]
    ir = band(band(ir, high=6500), low=200)
    ramp = int(0.014 * SR)
    ir[:ramp] *= np.linspace(0, 1, ramp)[:, None] ** 2
    return ir / np.sqrt((ir ** 2).sum(axis=0)).mean()


ROOM = room()


class Mix:
    """A stereo timeline. With loop=True events are laid twice and the second pass is kept, so
    ringing strings and the room's tail wrap round the loop point."""

    def __init__(self, seconds: float, loop: bool):
        self.length = int(round(seconds * SR))
        self.loop = loop
        self.total = self.length * (2 if loop else 1) + int(SR * 4)
        self.dry = np.zeros((self.total, 2))
        self.wet = np.zeros((self.total, 2))

    def add(self, sound: np.ndarray, at: float, gain: float = 1.0, pan: float = 0.0, send: float = 0.25) -> None:
        left = gain * np.cos((pan + 1) * np.pi / 4)
        right = gain * np.sin((pan + 1) * np.pi / 4)
        for start in ((int(at * SR), int(at * SR) + self.length) if self.loop else (int(at * SR),)):
            if start < 0:
                continue
            end = min(start + len(sound), self.total)
            part = sound[:end - start]
            self.dry[start:end, 0] += part * left
            self.dry[start:end, 1] += part * right
            self.wet[start:end, 0] += part * left * send
            self.wet[start:end, 1] += part * right * send

    def render(self) -> np.ndarray:
        out = self.dry.copy()
        for ch in range(2):
            out[:, ch] += fftconvolve(self.wet[:, ch], ROOM[:, ch])[:self.total] * 0.5
        out = band(out, low=62)
        out += 0.5 * band(out, low=2600, order=1)  # air: lifts the top octaves a few dB
        return out[self.length:self.length * 2] if self.loop else out[:self.length]


def save(name: str, audio: np.ndarray, folder: str = "music", quality: int = 5) -> None:
    out_dir = ROOT / "assets" / folder
    out_dir.mkdir(parents=True, exist_ok=True)
    temp = out_dir / (name + ".tmp.wav")
    pcm = (np.clip(audio, -1, 1) * 32767).astype("<i2")
    with wave.open(str(temp), "wb") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(pcm.tobytes())
    target = out_dir / (name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(temp), "-c:a", "libvorbis", "-q:a", str(quality), str(target)], check=True)
    temp.unlink()
    rms = 20 * np.log10(np.sqrt((audio ** 2).mean()) + 1e-9)
    print(f"{folder}/{name}.ogg  {len(audio) / SR:5.1f} s  peak {np.abs(audio).max():.2f}  rms {rms:5.1f} dB  {target.stat().st_size // 1024} KB")


def level(parts: list, peak: float = 0.84) -> list:
    """One gain for a set of loops that play together, so their sum peaks at `peak`."""
    gain = peak / np.abs(sum(parts)).max()
    return [p * gain for p in parts]


# ---- writing notes ----------------------------------------------------------------------------
def line(notes: str) -> list:
    """'D5:1 A4:.5 R:1' -> [(pitch or None, beats)], one bar after another."""
    out = []
    for token in notes.split():
        pitch, beats = token.split(":")
        out.append((None if pitch == "R" else pitch, float(beats)))
    return out


def human(amount: float = 0.006) -> float:
    return float(rng.normal(0, amount))


def play_tune(mix: Mix, bars: list, beat: float, start_beat: float = 0.0, gain: float = 0.5, pan: float = 0.15, octave: int = 0, doubled: bool = False) -> None:
    """A melody on the recorder; `doubled` adds the lute an octave below (plucked on every note)."""
    at = start_beat
    for bar in bars:
        for pitch, beats in line(bar):
            if pitch is not None:
                f = hz(pitch) * 2 ** octave
                mix.add(recorder(f, beats * beat * 0.94), at * beat + human(0.004), gain * float(rng.uniform(0.92, 1.05)), pan, 0.32)
                if doubled:
                    mix.add(pluck(f / 2, min(1.6, beats * beat + 0.5), 1.15), at * beat + human(0.004), gain * 0.55, -pan, 0.22)
            at += beats


CHORDS = {
    # bass, then the tones the lute picks from (low to high)
    "Dm": ("D2", ["A2", "D3", "F3", "A3", "D4", "F4"]),
    "C": ("C3", ["G2", "C3", "E3", "G3", "C4", "E4"]),
    "G": ("G2", ["D3", "G3", "B3", "D4", "G4"]),
    "Am": ("A2", ["E3", "A3", "C4", "E4", "A4"]),
    "F": ("F2", ["C3", "F3", "A3", "C4", "F4"]),
    "Bb": ("Bb2", ["F3", "Bb3", "D4", "F4"]),
    "Gm": ("G2", ["D3", "G3", "Bb3", "D4", "G4"]),
    "A": ("A2", ["E3", "A3", "C#4", "E4", "A4"]),
    "D": ("D2", ["A2", "D3", "F#3", "A3", "D4", "F#4"]),
}


def strum(mix: Mix, chord: str, at: float, gain: float = 0.5, spread: float = 0.022, ring: float = 2.4, pan: float = -0.2, up: bool = False) -> None:
    bass, tones = CHORDS[chord]
    notes = [bass] + tones
    if up:
        notes = notes[::-1]
    for i, name in enumerate(notes):
        mix.add(pluck(hz(name), ring, 1.1), at + i * spread + human(0.002), gain * (1.0 if i == 0 else 0.7) * float(rng.uniform(0.9, 1.05)), pan + i * 0.05, 0.3)


# ---- the pieces -------------------------------------------------------------------------------
def menu() -> None:
    """標題與選單：三拍子的魯特琴分解和弦，第二遍木笛進來。D Dorian，84 拍。"""
    beat = 60 / 84
    prog = ["Dm", "Dm", "C", "C", "Dm", "G", "Am", "Dm", "F", "C", "Dm", "Am", "F", "G", "Am", "Dm"]
    arps = {"Dm": ["A3", "D4", "F4", "D4", "A3"], "C": ["G3", "C4", "E4", "C4", "G3"], "G": ["B3", "D4", "G4", "D4", "B3"], "Am": ["A3", "C4", "E4", "C4", "A3"], "F": ["A3", "C4", "F4", "C4", "A3"]}
    tune = ["D5:2 E5:1", "F5:1 E5:1 D5:1", "C5:2 E5:1", "G4:3", "A4:1 D5:1 F5:1", "G5:2 F5:1", "E5:1.5 D5:.5 C5:1", "D5:3",
            "F5:2 A5:1", "G5:1 E5:1 C5:1", "D5:1 F5:1 A5:1", "E5:3", "F5:1 E5:1 D5:1", "B4:1 D5:1 G5:1", "E5:1.5 C5:.5 E5:1", "D5:3"]
    mix = Mix(32 * 3 * beat, True)
    for bar in range(32):
        chord = prog[bar % 16]
        t0 = bar * 3 * beat
        second = bar >= 16
        mix.add(pluck(hz(CHORDS[chord][0]), 3.2, 0.8), t0 + human(), 0.62, -0.1, 0.3)
        for i, name in enumerate(arps[chord]):
            mix.add(pluck(hz(name), 2.2, 0.95), t0 + (i + 1) * beat / 2 + human(), 0.36 * (1.12 if i == 2 else 1.0) * float(rng.uniform(0.88, 1.06)), -0.25 + i * 0.1, 0.3)
        if second and bar % 2 == 1:  # a bright answer high on the lute at the end of every other bar
            mix.add(pluck(hz(arps[chord][2]) * 2, 1.8, 1.2), t0 + 2.5 * beat + human(), 0.2, 0.45, 0.4)
    play_tune(mix, tune, beat, 16 * 3, 0.42, 0.2)
    save("menu", level([mix.render()], 0.8)[0])


def battle() -> None:
    """白天的戰鬥：三條等長的循環，依時辰一層層加上去。D Dorian，104 拍。"""
    beat = 60 / 104
    p1 = ["Dm", "Dm", "C", "Dm", "Dm", "F", "C", "Dm"]
    p2 = ["Dm", "G", "Dm", "C", "F", "C", "Am", "Dm"]
    p4 = ["F", "C", "Dm", "Am", "F", "G", "Am", "Dm"]
    prog = p1 + p2 + p1 + p4
    seconds = 32 * 4 * beat
    # Morning: the lute alone. Bass on one and three, chord tones between: a marching vamp.
    lute = Mix(seconds, True)
    for bar, chord in enumerate(prog):
        bass, tones = CHORDS[chord]
        fifth, octave, third = tones[0], tones[1], tones[2]
        upper = tones[3] if len(tones) > 3 else tones[-1]
        pattern = [bass, upper, tones[min(4, len(tones) - 1)], upper, fifth, tones[min(5, len(tones) - 1)], tones[min(4, len(tones) - 1)], upper]
        for i, name in enumerate(pattern):
            strong = i in (0, 4)
            lute.add(pluck(hz(name), 2.6 if strong else 1.5, 0.85 if strong else 1.05), (bar * 4 + i / 2) * beat + human(), (0.6 if strong else 0.33) * float(rng.uniform(0.9, 1.06)), -0.3 if strong else -0.15 + (i % 3) * 0.12, 0.26)
        _ = (octave, third)
    # Noon: the frame drum and the shaker join.
    drums = Mix(seconds, True)
    for bar in range(32):
        t0 = bar * 4 * beat
        fill = bar % 8 == 7
        for i in range(8):
            at = t0 + i * beat / 2 + human(0.004)
            drums.add(drum("shake"), at, 0.16 * (1.5 if i % 2 == 0 else 1.0), 0.5, 0.2)
            if i in (0, 3, 4) and not (fill and i == 4):
                drums.add(drum("dum"), at, 0.62 if i == 0 else 0.42, 0.05, 0.2)
            if i in (2, 6) and not fill:
                drums.add(drum("tak"), at, 0.34, 0.25, 0.25)
        if fill:  # a run of rim strokes into the next phrase
            for j in range(8):
                drums.add(drum("tak"), t0 + (2 + j / 4) * beat + human(0.003), 0.16 + 0.035 * j, 0.25, 0.25)
    # Dusk: the tune, and a second lute strumming on two and four.
    tune_a = ["D5:1 A4:.5 D5:.5 E5:1 F5:1", "E5:.5 D5:.5 E5:1 A4:2", "C5:1 G4:.5 C5:.5 D5:1 E5:1", "D5:2 R:1 A4:1",
              "D5:1 A4:.5 D5:.5 E5:1 F5:1", "A5:1.5 G5:.5 F5:1 E5:1", "E5:.5 D5:.5 C5:1 E5:1 C5:1", "D5:3 R:1"]
    tune_b = ["A5:1 A5:.5 G5:.5 F5:1 E5:1", "D5:1 B4:1 G4:1 B4:1", "D5:.5 E5:.5 F5:1 E5:1 D5:1", "C5:1.5 D5:.5 E5:2",
              "F5:1 A5:1 G5:.5 F5:.5 E5:1", "E5:1 G5:1 E5:1 C5:1", "E5:1 D5:.5 C5:.5 B4:1 C5:1", "D5:3 R:1"]
    tune_c = ["A5:1 F5:.5 A5:.5 C6:1 A5:1", "G5:1 E5:1 C5:1 E5:1", "F5:.5 E5:.5 D5:1 F5:1 A5:1", "E5:2 C5:1 E5:1",
              "F5:1 A5:1 C6:1 A5:1", "B5:1 G5:1 D5:1 G5:1", "E5:1 C5:.5 E5:.5 A5:1 E5:1", "D5:3 R:1"]
    tune = Mix(seconds, True)
    play_tune(tune, tune_a, beat, 0, 0.44, 0.2)
    play_tune(tune, tune_b, beat, 32, 0.44, 0.2)
    play_tune(tune, tune_a, beat, 64, 0.44, 0.2, doubled=True)
    play_tune(tune, tune_c, beat, 96, 0.46, 0.2, doubled=True)
    for bar, chord in enumerate(prog):
        for b in (1, 3):
            strum(tune, chord, (bar * 4 + b) * beat, 0.2, 0.012, 1.2, 0.35, up=b == 3)
    parts = level([lute.render(), drums.render(), tune.render()])
    for name, part in zip(("battle_lute", "battle_drums", "battle_tune"), parts):
        save(name, part)


def night() -> None:
    """入夜：城門朽壞的總攻。D 小調，132 拍，大鼓打 3＋3＋2。"""
    beat = 60 / 132
    n1 = ["Dm", "Dm", "Bb", "C", "Dm", "Dm", "Gm", "A"]
    n2 = ["Dm", "Dm", "Bb", "C", "Gm", "A", "Dm", "Dm"]
    n3 = ["F", "C", "Gm", "A", "Dm", "Bb", "Gm", "A"]
    prog = n1 + n2 + n3 + n2
    mix = Mix(32 * 4 * beat, True)
    for bar, chord in enumerate(prog):
        t0 = bar * 4 * beat
        bass, tones = CHORDS[chord]
        fill = bar % 8 == 7
        for i in range(8):
            at = t0 + i * beat / 2 + human(0.004)
            # Low lute: the root hammered in eighths, the fifth on the off beats.
            name = bass if i % 2 == 0 else tones[0]
            mix.add(pluck(hz(name), 1.3, 1.0), at, (0.46 if i in (0, 3, 6) else 0.28) * float(rng.uniform(0.92, 1.05)), -0.3, 0.22)
            if i in (0, 3, 6):
                mix.add(drum("war"), at, 0.5 if i == 0 else 0.36, 0.0, 0.3)
            if i in (2, 5) and not fill:
                mix.add(drum("tak"), at, 0.3, 0.3, 0.25)
            for half in range(2):
                mix.add(drum("shake"), at + half * beat / 4, 0.11 * (1.6 if half == 0 and i % 2 == 0 else 1.0), 0.55, 0.2)
        if fill:
            for j in range(8):
                mix.add(drum("dum"), t0 + (2 + j / 4) * beat + human(0.003), 0.2 + 0.05 * j, 0.1, 0.25)
        strum(mix, chord, t0 + beat, 0.16, 0.01, 1.0, 0.35)
        strum(mix, chord, t0 + 3 * beat, 0.16, 0.01, 1.0, 0.35, up=True)
    a = ["D5:.5 D5:.5 F5:.5 E5:.5 D5:1 A4:1", "D5:.5 D5:.5 F5:.5 G5:.5 A5:2", "Bb5:1 A5:.5 G5:.5 F5:1 D5:1", "E5:1 G5:1 E5:1 C5:1",
         "D5:.5 D5:.5 F5:.5 E5:.5 D5:1 A4:1", "D5:.5 E5:.5 F5:.5 G5:.5 A5:2", "Bb5:1 G5:1 D5:1 G5:1", "A5:1 E5:1 C#5:1 E5:1"]
    b = ["A5:.5 A5:.5 D6:1 A5:1 F5:1", "G5:.5 F5:.5 E5:.5 F5:.5 D5:2", "F5:1 D5:.5 F5:.5 Bb5:1 A5:1", "G5:1 E5:1 C5:1 E5:1",
         "D5:1 G5:.5 A5:.5 Bb5:1 G5:1", "A5:1.5 G5:.5 E5:1 C#5:1", "D5:1 A4:.5 D5:.5 F5:1 E5:1", "D5:3 R:1"]
    c = ["A5:1 F5:1 C5:1 F5:1", "G5:1 E5:1 C5:1 E5:1", "G5:.5 A5:.5 Bb5:1 A5:1 G5:1", "A5:2 E5:1 C#5:1",
         "D5:.5 D5:.5 F5:.5 E5:.5 D5:1 A4:1", "Bb4:1 D5:1 F5:1 Bb5:1", "A5:.5 G5:.5 F5:.5 G5:.5 Bb5:1 G5:1", "A5:1 C#5:1 E5:1 A5:1"]
    play_tune(mix, a, beat, 0, 0.42, 0.2, doubled=True)
    play_tune(mix, b, beat, 32, 0.42, 0.2, doubled=True)
    play_tune(mix, c, beat, 64, 0.42, 0.2, doubled=True)
    play_tune(mix, b, beat, 96, 0.44, 0.2, doubled=True)
    save("night", level([mix.render()])[0])


def victory() -> None:
    """勝利：D 大調的短號令，木笛往上、魯特琴掃弦、鈴鼓滾奏。"""
    beat = 60 / 120
    mix = Mix(9.0, False)
    strum(mix, "D", 0.0, 0.6, 0.02, 3.0)
    play_tune(mix, ["A4:.5 D5:.5 F#5:.5 A5:1.5", "B5:.5 A5:.5 G5:.5 A5:.5", "D6:5"], beat, 0, 0.5, 0.15, doubled=True)
    strum(mix, "G", 3 * beat, 0.5, 0.018, 2.4)
    strum(mix, "D", 5 * beat, 0.75, 0.03, 5.0)
    strum(mix, "D", 5 * beat + 0.5, 0.4, 0.02, 4.5, 0.3, up=True)
    for at, gain in ((0.0, 0.6), (3 * beat, 0.5), (5 * beat, 0.8)):
        mix.add(drum("dum"), at, gain, 0.0, 0.3)
    for j in range(22):  # shaker roll swelling under the last chord
        mix.add(drum("shake"), 5 * beat + j * 0.055, 0.1 + 0.25 * np.sin(np.pi * j / 22), 0.4, 0.3)
    audio = mix.render()
    audio[-SR:] *= np.linspace(1, 0, SR)[:, None]
    save("victory", level([audio], 0.88)[0])


def defeat() -> None:
    """敗北：D 小調往下走的一句，遠處一聲鐘。"""
    beat = 60 / 66
    mix = Mix(10.5, False)
    mix.add(bell(146.83, 6.0), 0.0, 0.5, -0.2, 0.5)
    for i, name in enumerate(["D2", "A2", "D3", "F3"]):
        mix.add(pluck(hz(name), 3.5, 0.8), i * beat / 2, 0.55, -0.2, 0.35)
    play_tune(mix, ["A4:1.5 G4:.5 F4:1 E4:1", "D4:4"], beat, 0, 0.5, 0.15)
    for i, name in enumerate(["Bb2", "F3", "Bb3"]):
        mix.add(pluck(hz(name), 3.0, 0.8), 2 * beat + i * 0.03, 0.4, -0.2, 0.35)
    for i, name in enumerate(["A2", "E3", "A3", "C#4"]):
        mix.add(pluck(hz(name), 3.0, 0.8), 3 * beat + i * 0.03, 0.4, -0.2, 0.35)
    for i, name in enumerate(["D2", "A2", "D3"]):
        mix.add(pluck(hz(name), 5.0, 0.75), 4 * beat + i * 0.05, 0.6, -0.2, 0.4)
    audio = mix.render()
    audio[-SR:] *= np.linspace(1, 0, SR)[:, None]
    save("defeat", level([audio], 0.8)[0])


def extras() -> None:
    """鐘聲（入夜）與介面的兩個小聲音：羽毛筆輕點、木塊一敲。"""
    mix = Mix(6.5, False)
    mix.add(bell(196.0, 6.0), 0.0, 1.0, 0.0, 0.45)
    audio = mix.render()
    audio[-SR:] *= np.linspace(1, 0, SR)[:, None]
    save("bell", level([audio], 0.8)[0], "audio")
    n = int(SR * 0.05)
    t = np.arange(n) / SR
    tick = band(rng.standard_normal(n), 2200, 6000) * np.exp(-t / 0.006) * 0.5
    save("ui_tick", level([np.stack([tick, tick], axis=1)], 0.45)[0], "audio")
    n = int(SR * 0.14)
    t = np.arange(n) / SR
    tock = np.sin(2 * np.pi * 640 * t) * np.exp(-t / 0.028) + 0.5 * np.sin(2 * np.pi * 1710 * t + 0.6) * np.exp(-t / 0.012) + band(rng.standard_normal(n), 400, 3000) * np.exp(-t / 0.005) * 0.6
    mix = Mix(0.4, False)
    mix.add(tock, 0.0, 1.0, 0.0, 0.12)
    save("ui_tock", level([mix.render()], 0.7)[0], "audio")


PIECES = {"menu": menu, "battle": battle, "night": night, "victory": victory, "defeat": defeat, "extras": extras}

if __name__ == "__main__":
    for name in (sys.argv[1:] or list(PIECES)):
        PIECES[name]()
