"""Synthesises the game's music and a few extra sounds. Original work, released CC0 with the game.

Acoustic timbres only (producer: no electronic sounds): a lute (plucked strings, additive
synthesis with stiff-string partials), a recorder, frame drums, a shaker and a church bell, in a
small stone room. Every run makes identical files (fixed seed).

    python tools/make_music.py            # everything
    python tools/make_music.py menu night # only these pieces

Needs numpy, scipy and ffmpeg. Output: assets/music/*.ogg, assets/audio/{bell,heal_chime,ui_tick,ui_tock}.ogg
The battle music is one theme per enemy faction (normal, magic, dark, beast), each four loops of the
same length that play together (music_player.gd raises them as the day goes on and whenever the
battle turns dangerous): battle_<theme>_lute, _drums, _tune and _tension.
    python tools/make_music.py battle:dark  # one theme only
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




# ---- retro-synth & hybrid percussion (2026-11-23) ---------------------------------------------
def _harmonic_stack(f0: float, t: np.ndarray, cutoff_arr: np.ndarray, slopes: float = 0.85, max_k: int = 22) -> np.ndarray:
    """Band-limited additive saw/brass stack with a sweeping low-pass contour."""
    lim = max(1, min(max_k, int(13000.0 / max(20.0, f0))))
    ks = np.arange(1, lim + 1, dtype=np.float64)[:, None]
    freqs = ks * f0
    mask = 1.0 / (1.0 + (freqs / np.maximum(cutoff_arr[None, :], 60.0)) ** 3.2)
    amps = mask / (ks ** slopes)
    return (amps * np.sin(2.0 * np.pi * freqs * t[None, :])).sum(axis=0)


def synth_brass(freq: float, dur: float, bright: float = 1.0) -> np.ndarray:
    """80s Jupiter-style punchy detuned synth brass: biting filter blat settling into warm lead."""
    key = ("sbrass", round(freq, 2), round(dur, 3), round(bright, 2))
    if key in _cache:
        return _cache[key]
    total_d = dur + 0.09
    n = max(64, int(SR * total_d))
    t = np.arange(n, dtype=np.float64) / SR
    vib = 0.0045 * np.clip((t - 0.14) / 0.14, 0.0, 1.0) * np.sin(2.0 * np.pi * 5.6 * t)
    scoop = 0.009 * np.exp(-t / 0.012)
    ph_t = np.cumsum(1.0 + vib + scoop) / SR
    cutoff = freq * (2.3 + 8.5 * bright * np.exp(-t / 0.13))
    out = np.zeros(n, dtype=np.float64)
    for det, w in ((0.9960, 0.34), (1.0000, 0.42), (1.0045, 0.34)):
        out += w * _harmonic_stack(freq * det, ph_t, cutoff, slopes=0.82, max_k=22)
    out += 0.22 * np.sin(2.0 * np.pi * (freq * 0.5) * ph_t)
    att = min(n, int(0.004 * SR))
    rel = min(n, int(0.025 * SR))
    env = np.ones(n, dtype=np.float64)
    if att > 0:
        env[:att] = np.linspace(0.0, 1.0, att)
    sust_end = min(n, int(dur * SR))
    if sust_end < n:
        env[sust_end:] = np.linspace(1.0, 0.0, n - sust_end) ** 1.4
    elif rel > 0:
        env[-rel:] *= np.linspace(1.0, 0.0, rel)
    out = out * env * 0.28
    out = band(out, low=95.0, order=1)
    _cache[key] = out
    return out


def synth_bass(freq: float, dur: float, punch: float = 1.0) -> np.ndarray:
    """Bouncy 80s slap/Moog funk synth bass with elastic FM attack."""
    key = ("sbass", round(freq, 2), round(dur, 3), round(punch, 2))
    if key in _cache:
        return _cache[key]
    n = max(64, int(SR * (dur + 0.05)))
    t = np.arange(n, dtype=np.float64) / SR
    fm_idx = 2.3 * punch * np.exp(-t / 0.026)
    mod = np.sin(2.0 * np.pi * (2.0 * freq) * t)
    cutoff = freq * (1.8 + 7.2 * punch * np.exp(-t / 0.055))
    saw = _harmonic_stack(freq, t, cutoff, slopes=0.92, max_k=14)
    core = np.sin(2.0 * np.pi * freq * t + fm_idx * mod) + 0.48 * saw
    env = np.minimum(t / 0.002, 1.0) * np.exp(-t / max(0.085, dur * 0.82))
    fade = min(n, int(0.015 * SR))
    if fade > 0:
        env[-fade:] *= np.linspace(1.0, 0.0, fade)
    out = band(core * env * 0.48, low=42.0, order=1)
    _cache[key] = out
    return out


def synth_arp(freq: float, dur: float, bright: float = 1.0) -> np.ndarray:
    """Crisp magical electric clav/bell pluck for rapid 16th arpeggios."""
    key = ("sarp", round(freq, 2), round(dur, 3), round(bright, 2))
    if key in _cache:
        return _cache[key]
    n = max(64, int(SR * (dur + 0.08)))
    t = np.arange(n, dtype=np.float64) / SR
    idx = (1.6 * bright) * np.exp(-t / 0.04)
    sig = np.sin(2.0 * np.pi * freq * t + idx * np.sin(2.0 * np.pi * (3.0 * freq) * t))
    sig += 0.45 * np.sin(2.0 * np.pi * (2.0 * freq) * t) * np.exp(-t / 0.09)
    env = np.minimum(t / 0.0015, 1.0) * np.exp(-t / max(0.07, dur * 0.9))
    fade = min(n, int(0.014 * SR))
    if fade > 0:
        env[-fade:] *= np.linspace(1.0, 0.0, fade)
    out = band(sig * env * 0.34, low=140.0, order=1)
    _cache[key] = out
    return out


def synth_stab(chord: str, dur: float = 0.16, bright: float = 1.0) -> np.ndarray:
    """Tight polyphonic synth-brass chord stab for offbeat accents."""
    key = ("sstab", chord, round(dur, 3), round(bright, 2))
    if key in _cache:
        return _cache[key]
    _, tones = CHORDS[chord]
    pick = tones[1:4] if len(tones) >= 4 else tones[-3:]
    n = max(64, int(SR * (dur + 0.06)))
    t = np.arange(n, dtype=np.float64) / SR
    out = np.zeros(n, dtype=np.float64)
    for idx_t, name in enumerate(pick):
        f0 = hz(name)
        cutoff = f0 * (2.0 + 7.5 * bright * np.exp(-t / 0.075))
        det = 1.0 + (idx_t - 1) * 0.0025
        out += _harmonic_stack(f0 * det, t, cutoff, slopes=0.95, max_k=14)
    env = np.minimum(t / 0.002, 1.0) * np.exp(-t / (dur * 0.65))
    fade = min(n, int(0.015 * SR))
    if fade > 0:
        env[-fade:] *= np.linspace(1.0, 0.0, fade)
    out = band(out * env * (0.20 / max(1, len(pick))), low=130.0, order=1)
    _cache[key] = out
    return out


def e_drum(kind: str) -> np.ndarray:
    """Punchy 80s hybrid percussion: kick, snare, clap, hat_c, hat_o, tom."""
    key = ("edrum", kind)
    if key in _cache:
        return _cache[key]
    r_local = np.random.default_rng(700 + sum(ord(c) for c in kind))
    if kind == "kick":
        n = int(SR * 0.34)
        t = np.arange(n) / SR
        f = 48.0 + 132.0 * np.exp(-t / 0.016)
        ph = 2.0 * np.pi * np.cumsum(f) / SR
        body = np.sin(ph) * np.exp(-t / 0.145)
        click = band(r_local.standard_normal(n), 900.0, 4800.0) * np.exp(-t / 0.004) * 0.55
        out = np.tanh((body + click) * 1.45) * 0.72
    elif kind == "snare":
        n = int(SR * 0.26)
        t = np.arange(n) / SR
        tone = np.sin(2.0 * np.pi * np.cumsum(148.0 + 68.0 * np.exp(-t / 0.014)) / SR) * np.exp(-t / 0.068) * 0.72
        gate = np.where(t < 0.075, 1.0, np.exp(-(t - 0.075) / 0.032))
        noise = band(r_local.standard_normal(n), 850.0, 7200.0) * gate * 0.65
        out = np.tanh((tone + noise) * 1.35) * 0.62
    elif kind == "clap":
        n = int(SR * 0.22)
        t = np.arange(n) / SR
        env = sum(np.where(t >= d, np.exp(-(t - d) / 0.012), 0.0) for d in (0.0, 0.010, 0.021, 0.032))
        tail = np.where(t >= 0.032, np.exp(-(t - 0.032) / 0.065), 0.0) * 0.85
        out = band(r_local.standard_normal(n), 1050.0, 4600.0) * (env * 0.45 + tail) * 0.48
    elif kind in ("hat_c", "hat_o"):
        dur = 0.065 if kind == "hat_c" else 0.23
        tau = 0.018 if kind == "hat_c" else 0.075
        n = int(SR * dur)
        t = np.arange(n) / SR
        metal = sum(np.sin(2.0 * np.pi * f * t + i) for i, f in enumerate((318.0, 476.0, 712.0, 1085.0, 1620.0)))
        noise = r_local.standard_normal(n)
        raw_h = band(metal * 0.25 + noise * 0.8, low=6200.0, order=2)
        out = raw_h * np.exp(-t / tau) * (0.28 if kind == "hat_c" else 0.26)
    else:  # tom
        n = int(SR * 0.30)
        t = np.arange(n) / SR
        f = 84.0 + 70.0 * np.exp(-t / 0.025)
        out = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.115) * 0.62
    fade = min(len(out), 180)
    out[-fade:] *= np.linspace(1.0, 0.0, fade)
    out[:min(len(out), 44)] *= np.linspace(0.0, 1.0, min(len(out), 44))
    _cache[key] = out
    return out


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

    def render(self, low_cut: float = 62.0) -> np.ndarray:
        out = self.dry.copy()
        for ch in range(2):
            out[:, ch] += fftconvolve(self.wet[:, ch], ROOM[:, ch])[:self.total] * 0.5
        out = band(out, low=low_cut)
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


def play_hybrid_tune(mix: Mix, bars: list, beat: float, start_beat: float = 0.0, gain: float = 0.48, pan: float = 0.12, doubled: bool = False, bright: float = 1.0) -> None:
    """Biting synth-brass hook layered with lute pluck; chorus sections add octave gleam + recorder."""
    at = start_beat
    for bar in bars:
        for pitch, beats in line(bar):
            if pitch is not None:
                f = hz(pitch)
                dur = beats * beat
                gate = 0.78 if beats <= 0.75 else (0.86 if beats <= 1.5 else 0.94)
                pos = at * beat + human(0.002)
                amp = gain * float(rng.uniform(0.95, 1.04))
                mix.add(synth_brass(f, dur * gate, bright), pos, amp, pan, 0.24)
                mix.add(pluck(f * 0.5, min(1.2, dur + 0.35), 1.3), pos, amp * 0.42, -pan * 1.4, 0.18)
                if doubled:
                    mix.add(synth_brass(f * 2.0, dur * gate * 0.9, bright * 1.05), pos, amp * 0.30, -pan, 0.28)
                    if beats >= 0.75:
                        mix.add(recorder(f, dur * 0.9), pos, amp * 0.26, pan * 1.3, 0.24)
            at += beats


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
    "Em": ("E2", ["B2", "E3", "G3", "B3", "E4", "G4"]),
    "B": ("B2", ["F#3", "B3", "D#4", "F#4", "B4"]),
    "Eb": ("Eb2", ["Bb2", "Eb3", "G3", "Bb3", "Eb4", "G4"]),
    "Cm": ("C3", ["G2", "C3", "Eb3", "G3", "C4", "Eb4"]),
    "Fm": ("F2", ["C3", "F3", "Ab3", "C4", "F4", "Ab4"]),
    "Db": ("Db2", ["Ab2", "Db3", "F3", "Ab3", "Db4", "F4"]),
    "Bbm": ("Bb2", ["F2", "Bb2", "Db3", "F3", "Bb3", "Db4"]),
    "Ab": ("Ab2", ["Eb3", "Ab3", "C4", "Eb4", "Ab4"]),
    "C7": ("C2", ["G2", "C3", "E3", "Bb3", "C4", "E4"]),
    "E7": ("E2", ["B2", "E3", "G#3", "D4", "E4", "G#4"]),
    "G7": ("G2", ["D3", "G3", "B3", "F4", "G4"]),
    "B7": ("B2", ["F#3", "B3", "D#4", "A4", "B4"]),
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
    """標題與選單：三拍子魯特琴分解和弦×溫暖合成貝斯與水晶音序，D Dorian，92 拍。"""
    beat = 60 / 92
    prog = ["Dm", "Dm", "C", "C", "Dm", "G", "Am", "Dm", "F", "C", "Dm", "Am", "F", "G", "Am", "Dm"]
    arps = {"Dm": ["A3", "D4", "F4", "D4", "A3"], "C": ["G3", "C4", "E4", "C4", "G3"], "G": ["B3", "D4", "G4", "D4", "B3"], "Am": ["A3", "C4", "E4", "C4", "A3"], "F": ["A3", "C4", "F4", "C4", "A3"]}
    tune = ["D5:2 E5:1", "F5:1 E5:1 D5:1", "C5:2 E5:1", "G4:3", "A4:1 D5:1 F5:1", "G5:2 F5:1", "E5:1.5 D5:.5 C5:1", "D5:3",
            "F5:2 A5:1", "G5:1 E5:1 C5:1", "D5:1 F5:1 A5:1", "E5:3", "F5:1 E5:1 D5:1", "B4:1 D5:1 G5:1", "E5:1.5 C5:.5 E5:1", "D5:3"]
    mix = Mix(32 * 3 * beat, True)
    for bar in range(32):
        chord = prog[bar % 16]
        t0 = bar * 3 * beat
        second = bar >= 16
        f_bass = hz(CHORDS[chord][0])
        mix.add(pluck(f_bass, 3.0, 0.85), t0 + human(), 0.56, -0.14, 0.28)
        mix.add(synth_bass(f_bass, 1.45 * beat, 0.72 if not second else 0.82), t0, 0.34 if not second else 0.40, -0.08, 0.14)
        for i, name in enumerate(arps[chord]):
            mix.add(pluck(hz(name), 2.1, 0.98), t0 + (i + 1) * beat / 2 + human(), 0.33 * (1.12 if i == 2 else 1.0) * float(rng.uniform(0.88, 1.06)), -0.25 + i * 0.1, 0.28)
            if second and i in (1, 3):
                mix.add(synth_arp(hz(name) * 2.0, beat * 0.45, 0.85), t0 + (i + 1) * beat / 2 + human(0.002), 0.11, 0.32 if i == 1 else -0.30, 0.26)
        if second:
            mix.add(synth_bass(hz(arps[chord][0]) * 0.5, 0.65 * beat, 0.74), t0 + 2.0 * beat, 0.24, 0.08, 0.14)
            mix.add(e_drum("kick"), t0, 0.36, 0.0, 0.12)
            mix.add(e_drum("hat_c"), t0 + 1.0 * beat, 0.12, 0.30, 0.12)
            mix.add(e_drum("hat_c"), t0 + 2.0 * beat, 0.14, -0.25, 0.12)
            mix.add(drum("shake"), t0 + 2.5 * beat, 0.11, 0.38, 0.18)
            if bar % 2 == 1:
                mix.add(pluck(hz(arps[chord][2]) * 2, 1.8, 1.25), t0 + 2.5 * beat + human(), 0.22, 0.45, 0.38)
    play_tune(mix, tune, beat, 16 * 3, 0.38, 0.20)
    play_hybrid_tune(mix, tune, beat, 16 * 3, 0.24, -0.14, doubled=False, bright=0.80)
    save("menu", level([mix.render(45.0)], 0.85)[0], quality=4)


# ---- battle themes (2026-11-22) --------------------------------------------------------------
# One theme per faction of the enemy lord: 經典 normal, 魔法 magic, 黑暗 dark, 魔物 beast. Each is 64 bars
# (two to three minutes before it repeats) in eight 8-bar sections, written as four loops of the same
# length that play in step (music_player.gd): lute (always), drums (from noon), tune (from dusk) and
# tension (raised whenever the battle turns dangerous or decisive).


def lute_bar(mix: Mix, style: str, chord: str, t0: float, beat: float, section: int) -> None:
    bass, tones = CHORDS[chord]
    top = tones[-1]
    if style == "vamp":  # bass on one and three, chord tones between: a marching vamp
        upper = tones[3] if len(tones) > 3 else tones[-1]
        pattern = [bass, upper, tones[min(4, len(tones) - 1)], upper, tones[0], tones[min(5, len(tones) - 1)], tones[min(4, len(tones) - 1)], upper]
        if section % 2 == 1:  # every other section breaks the chord upward instead
            pattern = [bass, tones[1], tones[2], tones[3 % len(tones)], tones[0], tones[2], tones[3 % len(tones)], top]
        for i, name in enumerate(pattern):
            strong = i in (0, 4)
            mix.add(pluck(hz(name), 2.6 if strong else 1.5, 0.85 if strong else 1.05), t0 + i * beat / 2 + human(), (0.6 if strong else 0.33) * float(rng.uniform(0.9, 1.06)), -0.3 if strong else -0.15 + (i % 3) * 0.12, 0.26)
    elif style == "arp":  # glassy broken chords, an octave bell-tone on the bar
        ring = tones + tones[-2:0:-1]
        mix.add(pluck(hz(bass), 3.0, 0.8), t0 + human(), 0.55, -0.25, 0.35)
        for i in range(8):
            name = ring[(i + section) % len(ring)]
            mix.add(pluck(hz(name), 1.8, 1.25), t0 + i * beat / 2 + human(), 0.3 * float(rng.uniform(0.88, 1.06)), -0.35 + (i % 4) * 0.2, 0.42)
        mix.add(pluck(hz(top) * 2, 2.4, 1.4), t0 + human(), 0.16, 0.5, 0.55)
    elif style == "drone":  # low strings left ringing; the dark theme adds a tolling bell per phrase
        mix.add(pluck(hz(bass), 4.5, 0.7), t0 + human(), 0.62, -0.2, 0.4)
        mix.add(pluck(hz(tones[0]), 3.5, 0.75), t0 + 2 * beat + human(), 0.4, -0.05, 0.4)
        for i, name in enumerate(tones[1:4]):
            mix.add(pluck(hz(name), 2.2, 0.9), t0 + (1 + i) * beat * 0.5 + 2 * beat + human(), 0.2, 0.15 + i * 0.1, 0.45)
    else:  # "riff": 3+3+2 hammered on the low strings
        for i in range(8):
            if i in (0, 3, 6):
                mix.add(pluck(hz(bass), 1.4, 0.9), t0 + i * beat / 2 + human(), 0.62, -0.3, 0.22)
                mix.add(pluck(hz(tones[0]), 1.2, 0.95), t0 + i * beat / 2 + 0.012, 0.34, -0.15, 0.22)
            elif i == 7:
                mix.add(pluck(hz(tones[1]), 0.8, 1.1), t0 + i * beat / 2 + human(), 0.36, 0.1, 0.2)
        strum(mix, chord, t0 + 2 * beat, 0.16, 0.01, 0.9, 0.3, up=True)


def drum_bar(mix: Mix, style: str, t0: float, beat: float, bar: int) -> None:
    fill = bar % 8 == 7
    for i in range(8):
        at = t0 + i * beat / 2 + human(0.004)
        if style == "march":
            mix.add(drum("shake"), at, 0.16 * (1.5 if i % 2 == 0 else 1.0), 0.5, 0.2)
            if i in (0, 3, 4) and not (fill and i == 4):
                mix.add(drum("dum"), at, 0.62 if i == 0 else 0.42, 0.05, 0.2)
            if i in (2, 6) and not fill:
                mix.add(drum("tak"), at, 0.34, 0.25, 0.25)
        elif style == "light":
            if i % 2 == 0 or bar % 2 == 1:
                mix.add(drum("shake"), at, 0.2 * (1.4 if i % 4 == 0 else 1.0), 0.45, 0.35)
            if i in (2, 6) and not fill:
                mix.add(drum("tak"), at, 0.4, 0.3, 0.4)
            if i == 0 or (i == 5 and bar % 2 == 1):
                mix.add(drum("dum"), at, 0.6 if i == 0 else 0.4, 0.0, 0.35)
        elif style == "heartbeat":
            if i in (0, 1):
                mix.add(drum("war"), at, 0.55 if i == 0 else 0.32, 0.0, 0.35)
            if i == 6 and bar % 2 == 1 and not fill:
                mix.add(drum("tak"), at, 0.22, 0.3, 0.45)
            if i in (2, 6):
                mix.add(drum("shake"), at, 0.08, 0.5, 0.4)
        else:  # "tribal"
            if i in (0, 3, 6):
                mix.add(drum("war"), at, 0.58 if i == 0 else 0.44, 0.0, 0.25)
            if i in (2, 5) and not fill:
                mix.add(drum("dum"), at, 0.34, -0.15, 0.25)
            if i == 4:
                mix.add(drum("tak"), at, 0.32, 0.3, 0.25)
            for half in range(2):
                mix.add(drum("shake"), at + half * beat / 4, 0.1 * (1.5 if half == 0 else 1.0), 0.55, 0.2)
    if fill:  # a run of strokes into the next phrase
        for j in range(8):
            mix.add(drum("dum" if style == "heartbeat" else "tak"), t0 + (2 + j / 4) * beat + human(0.003), 0.16 + 0.035 * j, 0.25, 0.25)


def tension_bar(mix: Mix, chord: str, t0: float, beat: float, bar: int) -> None:
    """The danger layer: war drum on every eighth, the root hammered low, a high ostinato on the chord."""
    bass, tones = CHORDS[chord]
    high = tones[-3:]
    for i in range(8):
        at = t0 + i * beat / 2 + human(0.003)
        accent = i in (0, 3, 6)
        mix.add(drum("war"), at, 0.5 if accent else 0.24, 0.0, 0.22)
        mix.add(pluck(hz(bass), 0.4, 0.8), at, 0.42 if accent else 0.26, -0.35, 0.15)
        mix.add(pluck(hz(high[i % 3]) * 2, 0.7, 1.3), at + 0.008, 0.2 if accent else 0.13, 0.4, 0.3)
    if bar % 4 == 3:  # a rim roll into the next four bars
        for j in range(8):
            mix.add(drum("tak"), t0 + (2 + j / 4) * beat, 0.18 + 0.04 * j, 0.2, 0.2)


# ---- high-energy hybrid themes (Axel-F bounce × medieval parchment, 2026-11-23) -----------------
BASS_GROOVES = {
    "march": [
        (0, 0, 2.2, 1.00), (3, 1, 1.3, 0.84), (4, 0, 1.8, 0.88), (6, 2, 1.5, 0.86),
        (8, 0, 2.0, 0.96), (11, 1, 1.3, 0.86), (12, 2, 1.6, 0.90), (14, 1, 1.4, 0.84),
    ],
    "arp": [
        (0, 0, 2.4, 1.00), (2, 1, 1.4, 0.82), (4, 2, 1.5, 0.84), (6, 1, 1.4, 0.80),
        (8, 0, 2.2, 0.96), (10, 2, 1.4, 0.82), (12, 1, 1.5, 0.86), (14, 3, 1.3, 0.82),
    ],
    "heartbeat": [
        (0, 0, 2.6, 1.00), (3, 0, 1.5, 0.86), (6, 2, 1.4, 0.78),
        (8, 0, 2.4, 0.96), (11, 1, 1.5, 0.88), (14, 2, 1.3, 0.80),
    ],
    "tribal": [
        (0, 0, 2.0, 1.00), (3, 1, 1.2, 0.86), (6, 0, 2.0, 0.96), (8, 2, 1.3, 0.84),
        (10, 1, 1.3, 0.86), (12, 0, 1.8, 0.94), (14, 2, 1.2, 0.86),
    ],
    "axel": [
        (0, 0, 2.2, 1.00), (3, 1, 1.4, 0.88), (4, 0, 1.6, 0.78), (6, 2, 1.6, 0.90),
        (8, 1, 2.0, 0.95), (10, 0, 1.5, 0.82), (11, 2, 1.3, 0.84), (12, 0, 1.8, 0.92), (14, 1, 1.5, 0.88),
    ],
    "gallop": [
        (0, 0, 1.8, 1.00), (2, 0, 1.3, 0.76), (3, 1, 1.3, 0.88), (4, 0, 1.8, 0.88), (6, 2, 1.5, 0.86),
        (8, 0, 1.8, 0.96), (10, 0, 1.3, 0.76), (11, 1, 1.3, 0.88), (12, 2, 1.6, 0.90), (14, 1, 1.4, 0.88), (15, 2, 0.9, 0.72),
    ],
    "funk": [
        (0, 0, 2.0, 1.00), (3, 1, 1.2, 0.90), (6, 0, 1.4, 0.85), (7, 2, 1.2, 0.78),
        (8, 1, 1.8, 0.95), (10, 2, 1.4, 0.84), (12, 0, 1.6, 0.90), (14, 3, 1.3, 0.86), (15, 1, 0.9, 0.75),
    ],
    "blitz": [
        (0, 0, 1.5, 1.00), (2, 1, 1.2, 0.82), (4, 0, 1.5, 0.92), (6, 2, 1.2, 0.84),
        (8, 0, 1.5, 0.98), (10, 1, 1.2, 0.84), (11, 0, 1.0, 0.76), (12, 2, 1.5, 0.92), (14, 1, 1.4, 0.88),
    ],
}


def hybrid_base_bar(mix: Mix, groove: str, chord: str, t0: float, beat: float, bar: int) -> None:
    bass, tones = CHORDS[chord]
    f_root = hz(bass)
    f_oct = f_root * 2.0
    f_fifth = hz(tones[0]) if len(tones) > 0 else f_root * 1.5
    f_hi = hz(tones[min(2, len(tones) - 1)])
    pitches = (f_root, f_oct, f_fifth, f_hi)
    s16 = beat / 4.0
    bright_b = 0.86 if groove == "heartbeat" else 1.0
    for step, deg, gate16, weight in BASS_GROOVES[groove]:
        at = t0 + step * s16 + human(0.002)
        f = pitches[deg]
        mix.add(synth_bass(f, gate16 * s16, (0.95 if weight > 0.85 else 0.78) * bright_b), at, 0.56 * weight, -0.10, 0.10)
        if step in (0, 6, 8, 14) or (groove == "heartbeat" and step in (3, 11)):
            mix.add(pluck(f * 2.0, 0.85, 1.25), at, 0.22 * weight, -0.28, 0.18)
    arp_idx = (1, 2, 3, 2, 1, 3)
    for k_i, step in enumerate((2, 4, 7, 10, 13, 15)):
        note_name = tones[arp_idx[k_i] % len(tones)]
        mix.add(synth_arp(hz(note_name), s16 * 1.4, 1.05 if groove == "arp" else 0.95), t0 + step * s16 + human(0.002), 0.14 if step in (2, 10) else 0.10, 0.34 - (k_i % 2) * 0.22, 0.24)
    if groove == "arp":
        mix.add(pluck(hz(tones[-1]) * 2.0, 1.8, 1.35), t0 + human(0.002), 0.16, 0.44, 0.36)
        for st in (0, 6, 8, 12):
            mix.add(synth_arp(hz(tones[st % len(tones)]) * 2.0, s16 * 1.2, 1.1), t0 + st * s16, 0.09, -0.35 if st % 8 == 0 else 0.35, 0.30)
    if bar % 2 == 1:
        strum(mix, chord, t0 + 3.5 * beat, 0.14, 0.009, 0.55, -0.32, up=True)


def hybrid_drum_bar(mix: Mix, style: str, t0: float, beat: float, bar: int) -> None:
    s16 = beat / 4.0
    fill4 = (bar % 8 == 3)
    fill8 = (bar % 8 == 7)
    kick_map = {
        "march": (0, 4, 6, 8, 12, 14),
        "arp": (0, 6, 8, 12, 14),
        "heartbeat": (0, 3, 8, 11),
        "tribal": (0, 3, 6, 8, 12, 14),
        "axel": (0, 6, 8, 14),
        "funk": (0, 6, 8, 14),
    }
    kicks = kick_map.get(style, (0, 4, 8, 12, 14))
    war_steps = (0, 3, 6) if style == "tribal" else ((0, 3, 8, 11) if style == "heartbeat" else (0, 8))
    for step in range(16):
        at = t0 + step * s16 + human(0.002)
        if step in kicks or (style in ("axel", "funk") and step == 12 and bar % 2 == 0):
            primary = step in ((0, 6, 12) if style == "tribal" else ((0, 3, 8, 11) if style == "heartbeat" else (0, 8)))
            mix.add(e_drum("kick"), at, 0.74 if primary else 0.54, 0.0, 0.08)
        if step in war_steps:
            mix.add(drum("war"), at, 0.30 if step in (0, 8) else 0.24, 0.0, 0.18)
        if step in (4, 12) and not (fill8 and step == 12):
            mix.add(e_drum("snare"), at, 0.62, 0.05, 0.20)
            mix.add(e_drum("clap"), at + 0.003, 0.36, -0.18 if step == 4 else 0.18, 0.24)
            if style in ("march", "tribal"):
                mix.add(drum("tak"), at, 0.18, 0.22, 0.20)
        if not (fill8 and step >= 12):
            if step == 14 and style != "blitz" or (style == "arp" and step == 10):
                mix.add(e_drum("hat_o"), at, 0.28, 0.42, 0.18)
            elif step % 2 == 0 or style in ("blitz", "axel", "arp", "tribal"):
                accent = 1.25 if step % 4 == 2 else (0.95 if step % 4 == 0 else 0.56)
                mix.add(e_drum("hat_c"), at, 0.22 * accent, 0.38 if step % 2 == 0 else -0.35, 0.10)
        if step in (2, 10) and style in ("axel", "funk", "march"):
            mix.add(drum("shake"), at, 0.14, -0.45, 0.16)
    if fill4:
        for j, st in enumerate((12, 14, 15)):
            mix.add(e_drum("tom" if j < 2 else "snare"), t0 + st * s16, 0.42 + 0.08 * j, -0.2 + 0.25 * j, 0.22)
    elif fill8:
        for j in range(6):
            kind = "tom" if j in (1, 2, 4) else "snare"
            mix.add(e_drum(kind), t0 + (10 + j) * s16 + human(0.002), 0.36 + 0.07 * j, -0.3 + 0.12 * j, 0.24)


def hybrid_tension_bar(mix: Mix, chord: str, t0: float, beat: float, bar: int) -> None:
    """Climax boost: rapid 16th synth-arp cascade + syncopated octave synth-brass power stabs + extra clap."""
    bass, tones = CHORDS[chord]
    pool = tones + tones[-2:0:-1]
    s16 = beat / 4.0
    for step in range(16):
        at = t0 + step * s16 + human(0.002)
        accent = step in (0, 3, 6, 8, 10, 14)
        note_name = pool[(step + bar) % len(pool)]
        mix.add(synth_arp(hz(note_name) * (2.0 if step % 4 == 2 else 1.0), s16 * 1.4, 1.2), at, 0.24 if accent else 0.15, -0.4 + (step % 4) * 0.26, 0.24)
        if accent:
            mix.add(synth_bass(hz(bass) * 2.0, s16 * 1.1, 1.05), at, 0.22, -0.15, 0.12)
        if step in (3, 6, 14):
            mix.add(synth_stab(chord, s16 * 1.6, 1.15), at, 0.34, 0.32 if step == 6 else -0.32, 0.28)
    if bar % 2 == 1:
        mix.add(e_drum("clap"), t0 + 14 * s16, 0.34, 0.0, 0.28)


THEMES = {
    "normal": {  # 經典・英勇行軍：D Dorian，118 拍，合成銅管行軍×魯特琴與電子戰鼓
        "hybrid": True, "bpm": 118, "groove": "march", "drums": "march", "gain": 0.44, "bright": 1.00, "stab_beats": (1.5, 3.5),
        "prog": {
            "p1": ["Dm", "Dm", "C", "Dm", "Dm", "F", "C", "Dm"], "p2": ["Dm", "G", "Dm", "C", "F", "C", "Am", "Dm"],
            "p4": ["F", "C", "Dm", "Am", "F", "G", "Am", "Dm"], "p5": ["Bb", "F", "C", "F", "Bb", "F", "Gm", "A"],
            "p6": ["Dm", "C", "Bb", "C", "Dm", "Am", "G", "A"]},
        "tunes": {
            "a": ["D5:1 A4:.5 D5:.5 E5:1 F5:1", "E5:.5 D5:.5 E5:1 A4:2", "C5:1 G4:.5 C5:.5 D5:1 E5:1", "D5:2 R:1 A4:1",
                  "D5:1 A4:.5 D5:.5 E5:1 F5:1", "A5:1.5 G5:.5 F5:1 E5:1", "E5:.5 D5:.5 C5:1 E5:1 C5:1", "D5:3 R:1"],
            "b": ["A5:1 A5:.5 G5:.5 F5:1 E5:1", "D5:1 B4:1 G4:1 B4:1", "D5:.5 E5:.5 F5:1 E5:1 D5:1", "C5:1.5 D5:.5 E5:2",
                  "F5:1 A5:1 G5:.5 F5:.5 E5:1", "E5:1 G5:1 E5:1 C5:1", "E5:1 D5:.5 C5:.5 B4:1 C5:1", "D5:3 R:1"],
            "c": ["A5:1 F5:.5 A5:.5 C6:1 A5:1", "G5:1 E5:1 C5:1 E5:1", "F5:.5 E5:.5 D5:1 F5:1 A5:1", "E5:2 C5:1 E5:1",
                  "F5:1 A5:1 C6:1 A5:1", "B5:1 G5:1 D5:1 G5:1", "E5:1 C5:.5 E5:.5 A5:1 E5:1", "D5:3 R:1"],
            "d": ["F5:2 D5:1 C5:1", "C5:1 A4:1 F4:2", "E5:1 G5:1 C6:1 G5:1", "A5:3 R:1",
                  "D6:1.5 C6:.5 Bb5:1 A5:1", "A5:1 G5:1 F5:2", "G5:1 Bb5:1 G5:1 D5:1", "E5:2 C#5:2"],
            "e": ["D5:.5 E5:.5 F5:1 A5:1 F5:1", "E5:1 G5:1 C5:1 E5:1", "D5:1 F5:1 Bb5:1 F5:1", "E5:1 G5:.5 F5:.5 E5:2",
                  "F5:.5 E5:.5 D5:1 A5:1 D6:1", "C6:1 A5:1 E5:1 A5:1", "B5:1 G5:1 D5:1 B4:1", "C#5:1 E5:1 A5:2"]},
        "form": [("p1", "a", 0), ("p2", "b", 0), ("p1", "a", 1), ("p4", "c", 1), ("p5", "d", 0), ("p6", "e", 0), ("p1", "a", 1), ("p4", "c", 1)]},
    "magic": {  # 魔法・奧術脈衝：E 小調，114 拍，水晶音序分解×合成銅管主旋律
        "hybrid": True, "bpm": 114, "groove": "arp", "drums": "arp", "gain": 0.44, "bright": 1.12, "stab_beats": (1.5, 3.5),
        "prog": {
            "m1": ["Em", "Em", "C", "B", "Em", "Am", "B", "Em"], "m2": ["Am", "Em", "C", "G", "Am", "F", "B", "B"],
            "m3": ["C", "D", "Em", "Em", "C", "D", "B", "B"], "m4": ["Em", "F", "Em", "F", "Am", "B", "Em", "Em"]},
        "tunes": {
            "a": ["E5:2 B4:1 E5:1", "G5:1.5 F#5:.5 E5:2", "E5:1 G5:1 C6:1 B5:1", "B5:2 D#5:2",
                  "E5:1 F#5:1 G5:1 B5:1", "A5:1.5 G5:.5 E5:1 C5:1", "D#5:1 F#5:1 B5:1 A5:1", "G5:2 E5:2"],
            "b": ["B5:1 A5:.5 G5:.5 E5:2", "E5:.5 F#5:.5 G5:1 B5:2", "C6:1 B5:1 G5:1 E5:1", "F#5:1 D#5:1 B4:2",
                  "E5:1 B4:1 E5:1 G5:1", "C6:1 A5:1 E5:1 A5:1", "B5:1 A5:1 F#5:1 D#5:1", "E5:4"],
            "c": ["A5:2 E5:1 C5:1", "B4:1 E5:1 G5:2", "G5:1 E5:1 C5:1 E5:1", "D5:1.5 B4:.5 G4:2",
                  "C5:1 E5:1 A5:1 C6:1", "A5:1 F5:1 C5:1 F5:1", "D#5:1 F#5:1 A5:1 B5:1", "B5:2 F#5:1 D#5:1"],
            "d": ["E5:1 G5:1 C6:2", "F#5:1 A5:1 D6:2", "B5:1.5 A5:.5 G5:1 E5:1", "E5:3 R:1",
                  "G5:1 E5:1 C5:1 E5:1", "A5:1 F#5:1 D5:1 F#5:1", "B5:2 A5:1 F#5:1", "D#5:2 B4:2"],
            "e": ["E5:1 B4:1 E5:1 G5:1", "F5:2 A5:1 C6:1", "B5:1 G5:1 E5:2", "A5:1 F5:1 C5:2",
                  "C5:1 E5:1 A5:1 E5:1", "D#5:1 F#5:1 B5:2", "G5:1 F#5:1 E5:1 B4:1", "E5:4"]},
        "form": [("m1", "a", 0), ("m1", "b", 0), ("m2", "c", 0), ("m3", "d", 0), ("m1", "a", 1), ("m4", "e", 0), ("m2", "c", 1), ("m3", "d", 1)]},
    "dark": {  # 黑暗・深淵喪鐘：D 小調／Phrygian，106 拍，雙拍心跳低音×宏鐘與重低音合成器
        "hybrid": True, "bpm": 106, "groove": "heartbeat", "drums": "heartbeat", "gain": 0.44, "bright": 0.92, "stab_beats": (1.5, 3.5), "bells": True,
        "prog": {
            "d1": ["Dm", "Dm", "Eb", "Dm", "Gm", "Gm", "A", "A"], "d2": ["Dm", "Bb", "Gm", "A", "Dm", "Eb", "Dm", "Dm"],
            "d3": ["Bb", "F", "Gm", "Dm", "Eb", "Bb", "A", "A"], "d4": ["Gm", "Dm", "Eb", "A", "Dm", "Eb", "Dm", "Dm"]},
        "tunes": {
            "a": ["D5:3 A4:1", "F5:2 E5:1 D5:1", "Eb5:2 D5:1 Bb4:1", "D5:4", "G5:2 F5:1 D5:1", "Bb4:1 D5:1 G5:2", "A5:2 G5:1 E5:1", "C#5:4"],
            "b": ["A4:1 D5:1 F5:1 A5:1", "Bb5:2 F5:2", "G5:1 F5:1 D5:1 Bb4:1", "C#5:2 E5:2", "F5:1.5 E5:.5 D5:2", "Eb5:1 G5:1 Bb5:2", "A5:1 F5:1 E5:1 D5:1", "D5:4"],
            "c": ["D5:2 F5:1 Bb5:1", "A5:2 C5:2", "Bb4:1 D5:1 G5:2", "F5:1 E5:1 D5:2", "Eb5:1 G5:1 Bb5:1 G5:1", "F5:2 D5:2", "E5:1 C#5:1 A4:2", "A4:4"],
            "d": ["G5:1 D5:1 Bb4:1 D5:1", "F5:2 A5:2", "G5:1.5 F5:.5 Eb5:2", "E5:2 C#5:2", "D5:1 F5:1 A5:1 D6:1", "C6:1 Bb5:1 G5:1 Eb5:1", "F5:1 E5:1 D5:1 C#5:1", "D5:4"]},
        "form": [("d1", "a", 0), ("d2", "b", 0), ("d1", "a", 1), ("d3", "c", 0), ("d4", "d", 0), ("d2", "b", 1), ("d3", "c", 1), ("d4", "d", 1)]},
    "beast": {  # 魔物・荒野狂踏：G 小調，128 拍，3＋3＋2 部落電鼓×野性銅管齊奏
        "hybrid": True, "bpm": 128, "groove": "tribal", "drums": "tribal", "gain": 0.44, "bright": 1.15, "stab_beats": (1.5, 3.0),
        "prog": {
            "b1": ["Gm", "Gm", "F", "Gm", "Gm", "Eb", "D", "Gm"], "b2": ["Cm", "Gm", "F", "Gm", "Eb", "Bb", "D", "D"],
            "b3": ["Eb", "F", "Gm", "Gm", "Eb", "F", "D", "D"]},
        "tunes": {
            "a": ["G5:1.5 G5:1.5 Bb5:1", "A5:1.5 G5:1.5 D5:1", "F5:1.5 A5:1.5 C6:1", "Bb5:2 G5:2",
                  "G5:1.5 Bb5:1.5 D6:1", "Eb6:1.5 D6:1.5 Bb5:1", "A5:1.5 F#5:1.5 D5:1", "G5:4"],
            "b": ["D6:1 Bb5:.5 G5:.5 D6:2", "C6:1.5 Bb5:1.5 A5:1", "C6:1 A5:1 F5:2", "G5:1.5 D5:1.5 G5:1",
                  "Bb5:1 D6:1 G6:2", "G5:1.5 Eb5:1.5 G5:1", "F#5:1 A5:1 D6:2", "G5:3 R:1"],
            "c": ["C6:1.5 G5:1.5 Eb5:1", "D5:1.5 G5:1.5 Bb5:1", "A5:1.5 F5:1.5 C5:1", "D5:2 G5:2",
                  "G5:1.5 Bb5:1.5 Eb6:1", "D6:1.5 Bb5:1.5 F5:1", "F#5:1 A5:1 D6:1 C6:1", "A5:2 F#5:2"],
            "d": ["G5:1 Bb5:1 Eb6:2", "F5:1 A5:1 C6:2", "D6:1.5 Bb5:1.5 G5:1", "G5:3 R:1",
                  "Eb6:1.5 D6:1.5 Bb5:1", "C6:1.5 A5:1.5 F5:1", "D5:1 F#5:1 A5:1 D6:1", "D6:2 A5:2"]},
        "form": [("b1", "a", 0), ("b1", "b", 0), ("b2", "c", 0), ("b1", "a", 1), ("b3", "d", 0), ("b2", "c", 1), ("b1", "b", 1), ("b3", "d", 1)]},
}


HYBRID_THEMES = {
    "conveyor": {  # 傳送帶・狂想曲：F 小調，126 拍，彈性合成貝斯＋16 分切分合成銅管＋大鍵琴對答
        "hybrid": True, "bpm": 126, "groove": "axel", "drums": "axel", "gain": 0.46, "bright": 1.08, "stab_beats": (1.5, 3.5),
        "prog": {
            "f1": ["Fm", "Fm", "Db", "Eb", "Fm", "Fm", "Eb", "C7"],
            "f2": ["Db", "Eb", "Fm", "Ab", "Bbm", "Fm", "Db", "C7"],
            "f3": ["Bbm", "Eb", "Ab", "Db", "Bbm", "C7", "Fm", "Fm"],
            "f4": ["Db", "Db", "Bbm", "Bbm", "Ab", "Eb", "C7", "C7"]},
        "tunes": {
            "a": ["F5:.75 Ab5:.75 F5:.5 F5:.25 Bb5:.5 F5:.5 Eb5:.75", "F5:.75 C6:.75 F5:.5 F5:.25 Db6:.5 C6:.5 Ab5:.75",
                  "F5:.5 C6:.5 F6:.5 F5:.25 Eb5:.5 Eb5:.25 C5:.5 G5:.5 G5:.5", "F5:2 R:.5 C5:.5 Eb5:.5 F5:.5",
                  "F5:.75 Ab5:.75 F5:.5 F5:.25 Bb5:.5 F5:.5 Eb5:.75", "F5:.75 C6:.75 F5:.5 Ab5:.5 Bb5:.5 C6:1",
                  "Eb6:.75 C6:.75 Bb5:.5 Ab5:.5 G5:.5 Eb5:1", "C6:.5 Bb5:.5 G5:.5 E5:.5 G5:.5 C6:.5 E5:1"],
            "b": ["Db5:.75 F5:.75 Ab5:.5 Eb5:.75 G5:.75 Bb5:.5", "C6:.5 Ab5:.5 F5:.5 C5:.5 Ab5:1.5 R:.5",
                  "Bb5:.75 F5:.75 Db5:.5 F5:.5 Ab5:.5 C6:1", "Ab5:.5 G5:.5 F5:.5 Eb5:.5 C5:1.5 R:.5",
                  "Db5:.75 F5:.75 Ab5:.5 Bb5:.5 C6:.5 Db6:1", "C6:.75 Ab5:.75 F5:.5 Eb5:.5 F5:.5 C6:1",
                  "Db6:.75 Bb5:.75 Ab5:.5 F5:.5 G5:.5 Eb5:1", "C6:.5 Bb5:.5 G5:.5 E5:.5 C5:1.5 R:.5"],
            "c": ["Bb5:.75 F5:.75 Db5:.5 Eb5:.75 G5:.75 Bb5:.5", "Ab5:.75 C6:.75 Eb6:.5 Db6:.5 C6:.5 Bb5:1",
                  "Ab5:.5 C6:.5 Eb6:.5 C6:.5 Db6:.75 Bb5:.75 F5:.5", "G5:.5 Bb5:.5 C6:.5 E5:.5 G5:1.5 R:.5",
                  "Bb5:.5 Db6:.5 F6:.5 Db6:.5 C6:.5 Ab5:.5 F5:.5 C5:.5", "Eb5:.75 G5:.75 Bb5:.5 C6:.5 E5:.5 G5:1",
                  "F5:.5 Ab5:.5 C6:.5 Eb6:.5 F6:1 C6:1", "F5:2 R:2"],
            "d": ["Db5:1.5 Ab5:1.5 F5:1", "Db5:1 F5:1 Ab5:1 Db6:1",
                  "Bb5:1.5 F5:1.5 Db5:1", "Bb4:1 Db5:1 F5:1 Bb5:1",
                  "Ab5:1.5 Eb5:1.5 C5:1", "Eb5:1 G5:1 Bb5:1 Eb6:1",
                  "C6:.5 G5:.5 E5:.5 G5:.5 C6:.5 Bb5:.5 G5:.5 E5:.5", "C6:.5 C6:.5 Bb5:.5 G5:.5 E5:1.5 R:.5"],
            "e": ["F5:.75 Ab5:.75 C6:.5 F6:.75 C6:.75 Bb5:.5", "Ab5:.75 G5:.75 F5:.5 Eb5:.5 F5:.5 C6:1",
                  "Db6:.75 Bb5:.75 F5:.5 Eb6:.75 C6:.75 G5:.5", "F6:1.5 Eb6:.5 C6:1 Ab5:1",
                  "F5:.75 Ab5:.75 F5:.5 Bb5:.75 F5:.75 Eb5:.5", "C6:.75 Ab5:.75 F5:.5 Db6:.75 C6:.75 Bb5:.5",
                  "Eb6:.5 Db6:.5 C6:.5 Bb5:.5 Ab5:.5 G5:.5 F5:.5 Eb5:.5", "F5:1 C6:1 F6:1.5 R:.5"]},
        "form": [("f1", "a", 0), ("f2", "b", 0), ("f1", "a", 1), ("f3", "c", 0), ("f4", "d", 0), ("f2", "b", 1), ("f3", "c", 1), ("f1", "e", 1)]},
    "charge": {  # 五路衝鋒・疾風號令：A 小調，130 拍，英雄式馳騁合成銅管＋戰鼓快節奏
        "hybrid": True, "bpm": 130, "groove": "gallop", "drums": "gallop", "gain": 0.46, "bright": 1.05, "stab_beats": (1.0, 2.5, 3.5),
        "prog": {
            "c1": ["Am", "Am", "F", "G", "Am", "F", "Dm", "E7"],
            "c2": ["F", "G", "Am", "Em", "F", "G", "E7", "Am"],
            "c3": ["Dm", "G", "C", "F", "Dm", "E7", "Am", "Am"],
            "c4": ["F", "F", "G", "G", "Dm", "Am", "E7", "E7"]},
        "tunes": {
            "a": ["A4:.5 C5:.5 E5:1 A5:.75 G5:.75 E5:.5", "A5:.5 G5:.5 E5:1 C5:1 D5:.5 E5:.5",
                  "F5:.75 A5:.75 C6:.5 G5:.75 B5:.75 D6:.5", "C6:1.5 B5:.5 A5:1 E5:1",
                  "A5:.75 E5:.75 C5:.5 F5:.75 C5:.75 A4:.5", "D5:.5 F5:.5 A5:1 G5:.5 F5:.5 E5:1",
                  "D5:.75 F5:.75 A5:.5 B5:.5 G#5:.5 E5:1", "A5:2 R:1 E5:.5 A5:.5"],
            "b": ["F5:1 C6:1 A5:.5 F5:.5 C6:1", "G5:1 D6:1 B5:.5 G5:.5 D6:1",
                  "E6:.75 C6:.75 A5:.5 B5:.5 G5:.5 E5:1", "A5:.5 B5:.5 C6:.5 D6:.5 E6:1.5 R:.5",
                  "F5:.75 A5:.75 C6:.5 G5:.75 B5:.75 D6:.5", "E6:1 C6:1 G5:1 E5:1",
                  "D5:.5 F5:.5 A5:.5 G#5:.5 B5:1 E5:1", "A5:2.5 R:1.5"],
            "c": ["D5:.75 F5:.75 A5:.5 G5:.75 B5:.75 D6:.5", "C6:.75 E6:.75 G5:.5 F5:.75 A5:.75 C6:.5",
                  "D6:.5 B5:.5 G#5:.5 E5:.5 E5:1 B5:1", "A5:.5 E5:.5 C5:.5 E5:.5 A5:1.5 R:.5",
                  "D6:.75 C6:.75 A5:.5 B5:.75 A5:.75 G5:.5", "C6:.75 G5:.75 E5:.5 F5:1 C6:1",
                  "D6:.5 C6:.5 B5:.5 A5:.5 G#5:1 E5:1", "A5:1.5 E5:.5 A5:1.5 R:.5"],
            "d": ["F5:1.5 C6:1.5 A5:1", "F5:1 A5:1 C6:1 F6:1",
                  "G5:1.5 D6:1.5 B5:1", "G5:1 B5:1 D6:1 G6:1",
                  "D6:1 A5:1 F5:1 D5:1", "E5:1 A5:1 C6:1 E6:1",
                  "E6:.5 D6:.5 B5:.5 G#5:.5 E5:.5 G#5:.5 B5:.5 D6:.5", "E6:2 R:2"],
            "e": ["A5:.75 C6:.75 E6:.5 A5:.75 G5:.75 E5:.5", "F5:.75 A5:.75 C6:.5 G5:.75 B5:.75 D6:.5",
                  "E6:.5 D6:.5 C6:.5 B5:.5 A5:.5 G5:.5 E5:.5 C5:.5", "D5:.5 F5:.5 A5:1 E5:1 G#5:1",
                  "A5:.75 E6:.75 C6:.5 F5:.75 C6:.75 A5:.5", "G5:.75 D6:.75 B5:.5 C6:.5 G5:.5 E5:1",
                  "F5:.5 D5:.5 B4:.5 G#5:.5 E5:1 B5:1", "A5:2.5 R:1.5"]},
        "form": [("c1", "a", 0), ("c2", "b", 0), ("c1", "a", 1), ("c3", "c", 0), ("c4", "d", 0), ("c2", "b", 1), ("c3", "c", 1), ("c1", "e", 1)]},
    "duel": {  # 鐵血交鋒・領主死鬥：C 小調，124 拍，放克彈跳合成貝斯＋犀利對切銅管＋大鍵琴花彩
        "hybrid": True, "bpm": 124, "groove": "funk", "drums": "funk", "gain": 0.45, "bright": 1.12, "stab_beats": (1.5, 3.0),
        "prog": {
            "u1": ["Cm", "Cm", "Eb", "Bb", "Cm", "Ab", "Fm", "G7"],
            "u2": ["Ab", "Bb", "Cm", "Gm", "Fm", "Cm", "Ab", "G7"],
            "u3": ["Fm", "Bb", "Eb", "Ab", "Fm", "G7", "Cm", "Cm"],
            "u4": ["Ab", "Ab", "Fm", "Fm", "Eb", "Bb", "G7", "G7"]},
        "tunes": {
            "a": ["C5:.75 Eb5:.75 G5:.5 R:.25 Bb5:.5 G5:.5 Eb5:.75", "C5:.75 G5:.75 Bb5:.5 C6:.5 Bb5:.5 G5:1",
                  "Eb5:.75 G5:.75 Bb5:.5 F5:.75 Bb5:.75 D6:.5", "C6:1.5 G5:.5 Eb5:1 C5:1",
                  "C6:.5 Bb5:.5 G5:.5 Eb5:.5 Ab5:.75 Eb5:.75 C5:.5", "F5:.5 Ab5:.5 C6:1 G5:.5 F5:.5 D5:1",
                  "C5:.5 D5:.5 Eb5:.5 F5:.5 G5:.75 B4:.75 D5:.5", "C5:1.5 G4:.5 C5:1.5 R:.5"],
            "b": ["Ab5:.75 C6:.75 Eb6:.5 Bb5:.75 D6:.75 F6:.5", "Eb6:.5 D6:.5 C6:.5 G5:.5 Eb5:1.5 R:.5",
                  "F5:.75 Ab5:.75 C6:.5 G5:.75 Bb5:.75 D6:.5", "C6:.5 Bb5:.5 Ab5:.5 G5:.5 Eb5:1.5 R:.5",
                  "Ab5:.75 Eb5:.75 C5:.5 F5:.75 C5:.75 Ab4:.5", "G5:.5 C6:.5 Eb6:1 D6:.5 C6:.5 G5:1",
                  "Ab5:.5 F5:.5 D5:.5 C5:.5 B4:1 G5:1", "C6:2 R:2"],
            "c": ["F5:.75 Ab5:.75 C6:.5 Bb5:.75 D6:.75 F5:.5", "Eb5:.75 G5:.75 Bb5:.5 Ab5:.75 C6:.75 Eb6:.5",
                  "F6:.5 D6:.5 Bb5:.5 Ab5:.5 G5:.5 F5:.5 D5:.5 B4:.5", "C5:.75 G5:.75 Eb5:.5 C5:1.5 R:.5",
                  "F5:.5 Ab5:.5 C6:.5 Ab5:.5 Bb5:.5 D6:.5 F6:1", "Eb6:.75 C6:.75 G5:.5 Ab5:1 Eb6:1",
                  "D6:.5 C6:.5 B5:.5 G5:.5 F5:1 D5:1", "C5:2 R:2"],
            "d": ["Ab5:1.5 Eb5:1.5 C5:1", "Ab4:1 C5:1 Eb5:1 Ab5:1",
                  "F5:1.5 C5:1.5 Ab4:1", "F5:1 Ab5:1 C6:1 F6:1",
                  "Eb6:1.5 Bb5:1.5 G5:1", "Bb5:1 D6:1 F6:1 Bb5:1",
                  "G5:.5 B5:.5 D6:.5 B5:.5 G5:.5 F5:.5 D5:.5 B4:.5", "G5:2 R:2"],
            "e": ["C5:.75 G5:.75 C6:.5 R:.25 Bb5:.5 G5:.5 Eb5:.75", "Eb5:.75 Bb5:.75 Eb6:.5 D6:.75 Bb5:.75 F5:.5",
                  "C6:.5 Bb5:.5 G5:.5 Eb5:.5 Ab5:.75 F5:.75 C5:.5", "D5:.5 F5:.5 G5:.5 B5:.5 D6:1 G5:1",
                  "C6:.75 Eb6:.75 G6:.5 C6:.75 Ab5:.75 Eb5:.5", "F5:.75 Ab5:.75 C6:.5 G5:.5 D6:.5 B5:1",
                  "Eb6:.5 D6:.5 C6:.5 Bb5:.5 Ab5:.5 G5:.5 F5:.5 D5:.5", "C5:1 G5:1 C6:1.5 R:.5"]},
        "form": [("u1", "a", 0), ("u2", "b", 0), ("u1", "a", 1), ("u3", "c", 0), ("u4", "d", 0), ("u2", "b", 1), ("u3", "c", 1), ("u1", "e", 1)]},
    "crimson": {  # 赤旗總攻・破陣之歌：E 小調，134 拍，高燃雙拍衝鋒與大考終極戰歌
        "hybrid": True, "bpm": 134, "groove": "blitz", "drums": "blitz", "gain": 0.45, "bright": 1.10, "stab_beats": (1.5, 3.5),
        "prog": {
            "r1": ["Em", "Em", "C", "D", "Em", "C", "Am", "B7"],
            "r2": ["C", "D", "Em", "G", "Am", "Em", "C", "B7"],
            "r3": ["Am", "D", "G", "C", "F", "Em", "B7", "Em"],
            "r4": ["F", "F", "Em", "Em", "C", "Am", "B7", "B7"]},
        "tunes": {
            "a": ["E5:.75 G5:.75 B5:.5 E6:.75 D6:.75 B5:.5", "E5:.75 G5:.75 B5:.5 C6:.5 B5:.5 A5:.5 G5:.5",
                  "C5:.75 E5:.75 G5:.5 D5:.75 F#5:.75 A5:.5", "B5:1.5 G5:.5 E5:1 B4:1",
                  "E5:.5 G5:.5 B5:.5 E6:.5 C6:.75 G5:.75 E5:.5", "A5:.5 C6:.5 E6:1 D6:.5 C6:.5 B5:1",
                  "A5:.5 G5:.5 F#5:.5 E5:.5 D#5:1 B4:1", "E5:2 R:1 B4:.5 E5:.5"],
            "b": ["C5:.75 G5:.75 E5:.5 D5:.75 A5:.75 F#5:.5", "E5:.5 G5:.5 B5:.5 E6:.5 B5:1.5 R:.5",
                  "G5:.75 B5:.75 D6:.5 C6:.75 A5:.75 E5:.5", "F#5:.5 A5:.5 B5:.5 D#6:.5 E6:1.5 R:.5",
                  "C6:.75 G5:.75 E5:.5 A5:.75 E5:.75 C5:.5", "B5:.5 E6:.5 G6:1 F#6:.5 E6:.5 B5:1",
                  "C6:.5 A5:.5 F#5:.5 D#5:.5 B4:1 F#5:1", "E5:2.5 R:1.5"],
            "c": ["A5:.75 C6:.75 E6:.5 D6:.75 A5:.75 F#5:.5", "G5:.75 B5:.75 D6:.5 C6:.75 G5:.75 E5:.5",
                  "F5:.5 A5:.5 C6:.5 A5:.5 E5:1 B5:1", "D#5:.5 F#5:.5 B5:.5 D#6:.5 E6:1.5 R:.5",
                  "A5:.5 C6:.5 E6:.5 A6:.5 G6:.75 E6:.75 B5:.5", "C6:.5 G5:.5 E5:.5 C5:.5 F5:1 C6:1",
                  "B5:.5 A5:.5 G5:.5 F#5:.5 D#5:1 B4:1", "E5:2 R:2"],
            "d": ["F5:1.5 C6:1.5 A5:1", "F5:1 A5:1 C6:1 F6:1",
                  "E5:1.5 B5:1.5 G5:1", "E5:1 G5:1 B5:1 E6:1",
                  "C6:.5 G5:.5 E5:.5 G5:.5 A5:.5 E5:.5 C5:.5 E5:.5", "B5:1 D#5:1 F#5:1 B5:1",
                  "B5:.5 F#5:.5 D#5:.5 F#5:.5 B5:.5 A5:.5 F#5:.5 D#5:.5", "B4:2 R:2"],
            "e": ["E5:.75 B5:.75 E6:.5 G6:.75 F#6:.75 E6:.5", "D6:.75 B5:.75 G5:.5 A5:.5 C6:.5 E6:1",
                  "C6:.75 G5:.75 E5:.5 D6:.75 A5:.75 F#5:.5", "E6:1.5 D6:.5 B5:1 G5:1",
                  "E5:.75 G5:.75 B5:.5 E6:.75 C6:.75 G5:.5", "D6:.75 A5:.75 F#5:.5 B5:.75 F#5:.75 D#5:.5",
                  "E5:.5 G5:.5 B5:.5 E6:.5 F#6:.5 D#6:.5 B5:.5 F#5:.5", "E5:1 B5:1 E6:1.5 R:.5"]},
        "form": [("r1", "a", 0), ("r2", "b", 0), ("r1", "a", 1), ("r3", "c", 0), ("r4", "d", 0), ("r2", "b", 1), ("r3", "c", 1), ("r1", "e", 1)]},
}
THEMES.update(HYBRID_THEMES)

def _assert_bar_beats(tunes: dict) -> None:
    for tk, p_bars in tunes.items():
        for bi, bar_s in enumerate(p_bars):
            total_b = sum(b for _, b in line(bar_s))
            assert abs(total_b - 4.0) < 1e-6, f"Tune {tk} bar {bi} has {total_b} beats (expected 4.0): {bar_s}"


def theme(name: str) -> None:
    th = THEMES[name]
    _assert_bar_beats(th["tunes"])
    beat = 60 / th["bpm"]
    seconds = 64 * 4 * beat
    lute, drums, tune, tension = (Mix(seconds, True) for _ in range(4))
    hybrid = bool(th.get("hybrid", False))
    bar = 0
    for section, (prog_key, tune_key, doubled) in enumerate(th["form"]):
        if hybrid:
            play_hybrid_tune(tune, th["tunes"][tune_key], beat, bar * 4, th["gain"], 0.12, bool(doubled), float(th.get("bright", 1.0)))
        else:
            play_tune(tune, th["tunes"][tune_key], beat, bar * 4, th["gain"], 0.2, doubled=bool(doubled))
        for chord in th["prog"][prog_key]:
            t0 = bar * 4 * beat
            if hybrid:
                hybrid_base_bar(lute, th["groove"], chord, t0, beat, bar)
                hybrid_drum_bar(drums, th["drums"], t0, beat, bar)
                for sb in th.get("stab_beats", (1.5, 3.5)):
                    tune.add(synth_stab(chord, 0.14, float(th.get("bright", 1.0))), t0 + sb * beat, 0.24, 0.30, 0.22)
                for b in (1, 3):
                    strum(tune, chord, t0 + b * beat, 0.12, 0.010, 0.85, -0.35, up=b == 3)
                hybrid_tension_bar(tension, chord, t0, beat, bar)
            else:
                lute_bar(lute, th["lute"], chord, t0, beat, section)
                drum_bar(drums, th["drums"], t0, beat, bar)
                for b in (1, 3):  # a second lute strums on two and four under the tune
                    strum(tune, chord, t0 + b * beat, 0.17, 0.012, 1.2, 0.35, up=b == 3)
                tension_bar(tension, chord, t0, beat, bar)
            if th.get("bells") and bar % 8 == 0:
                lute.add(bell(hz(CHORDS[chord][0]) * 2, 6.0), t0, 0.24, 0.3, 0.5)
            bar += 1
    lc = 45.0 if hybrid else 62.0
    parts = level([lute.render(lc), drums.render(lc), tune.render(lc), tension.render(lc)], 0.86 if hybrid else 0.84)
    for layer, part in zip(("lute", "drums", "tune", "tension"), parts):
        save(f"battle_{name}_{layer}", part, quality=4 if hybrid else 3)


def battle(*names: str) -> None:
    for name in names or THEMES:
        theme(name)


def night() -> None:
    """入夜：城門朽壞的總攻。D 小調，136 拍，3＋3＋2 狂飆合成貝斯×電戰鼓×警鐘銅管。"""
    beat = 60 / 136
    s16 = beat / 4.0
    n1 = ["Dm", "Dm", "Bb", "C", "Dm", "Dm", "Gm", "A"]
    n2 = ["Dm", "Dm", "Bb", "C", "Gm", "A", "Dm", "Dm"]
    n3 = ["F", "C", "Gm", "A", "Dm", "Bb", "Gm", "A"]
    prog = n1 + n2 + n3 + n2
    mix = Mix(32 * 4 * beat, True)
    for bar, chord in enumerate(prog):
        t0 = bar * 4 * beat
        bass, tones = CHORDS[chord]
        f_bass = hz(bass)
        fill = bar % 8 == 7
        if bar % 8 == 0:
            mix.add(bell(f_bass * 2.0, 5.5), t0, 0.24, 0.30, 0.45)
        for i in range(8):
            at = t0 + i * beat / 2 + human(0.003)
            name = bass if i % 2 == 0 else tones[0]
            accent = i in (0, 3, 6)
            mix.add(synth_bass(hz(name) if not accent else f_bass, beat * (0.55 if accent else 0.35), 1.05 if accent else 0.82), at, 0.48 if accent else 0.28, -0.10, 0.12)
            mix.add(pluck(hz(name), 1.1, 1.1), at, (0.30 if accent else 0.18) * float(rng.uniform(0.92, 1.05)), -0.30, 0.18)
            if accent:
                mix.add(drum("war"), at, 0.38 if i == 0 else 0.28, 0.0, 0.24)
        for step in range(16):
            at = t0 + step * s16 + human(0.002)
            if step in (0, 3, 6, 8, 12, 14):
                mix.add(e_drum("kick"), at, 0.66 if step in (0, 6, 8) else 0.48, 0.0, 0.08)
            if step in (4, 12) and not (fill and step == 12):
                mix.add(e_drum("snare"), at, 0.58, 0.05, 0.18)
                mix.add(e_drum("clap"), at + 0.003, 0.34, -0.18 if step == 4 else 0.18, 0.22)
                mix.add(drum("tak"), at, 0.20, 0.25, 0.20)
            if not (fill and step >= 12):
                if step == 14:
                    mix.add(e_drum("hat_o"), at, 0.26, 0.40, 0.16)
                elif step % 2 == 0 or step in (3, 7, 11, 15):
                    mix.add(e_drum("hat_c"), at, 0.19 if step % 2 == 0 else 0.11, 0.35 if step % 2 == 0 else -0.35, 0.10)
            arp_note = tones[(step + bar) % len(tones)]
            mix.add(synth_arp(hz(arp_note) * (2.0 if step % 4 == 2 else 1.0), s16 * 1.35, 1.08), at, 0.14 if step % 3 == 0 else 0.09, -0.35 + (step % 4) * 0.24, 0.22)
        if fill:
            for j in range(6):
                mix.add(e_drum("tom" if j in (1, 2, 4) else "snare"), t0 + (10 + j) * s16 + human(0.002), 0.34 + 0.07 * j, -0.3 + 0.12 * j, 0.22)
        for sb in (1.5, 3.5):
            mix.add(synth_stab(chord, 0.14, 1.12), t0 + sb * beat, 0.22, 0.30, 0.20)
        strum(mix, chord, t0 + beat, 0.12, 0.01, 0.9, -0.35)
        strum(mix, chord, t0 + 3 * beat, 0.12, 0.01, 0.9, -0.35, up=True)
    a = ["D5:.5 D5:.5 F5:.5 E5:.5 D5:1 A4:1", "D5:.5 D5:.5 F5:.5 G5:.5 A5:2", "Bb5:1 A5:.5 G5:.5 F5:1 D5:1", "E5:1 G5:1 E5:1 C5:1",
         "D5:.5 D5:.5 F5:.5 E5:.5 D5:1 A4:1", "D5:.5 E5:.5 F5:.5 G5:.5 A5:2", "Bb5:1 G5:1 D5:1 G5:1", "A5:1 E5:1 C#5:1 E5:1"]
    b = ["A5:.5 A5:.5 D6:1 A5:1 F5:1", "G5:.5 F5:.5 E5:.5 F5:.5 D5:2", "F5:1 D5:.5 F5:.5 Bb5:1 A5:1", "G5:1 E5:1 C5:1 E5:1",
         "D5:1 G5:.5 A5:.5 Bb5:1 G5:1", "A5:1.5 G5:.5 E5:1 C#5:1", "D5:1 A4:.5 D5:.5 F5:1 E5:1", "D5:3 R:1"]
    c = ["A5:1 F5:1 C5:1 F5:1", "G5:1 E5:1 C5:1 E5:1", "G5:.5 A5:.5 Bb5:1 A5:1 G5:1", "A5:2 E5:1 C#5:1",
         "D5:.5 D5:.5 F5:.5 E5:.5 D5:1 A4:1", "Bb4:1 D5:1 F5:1 Bb5:1", "A5:.5 G5:.5 F5:.5 G5:.5 Bb5:1 G5:1", "A5:1 C#5:1 E5:1 A5:1"]
    play_hybrid_tune(mix, a, beat, 0, 0.44, 0.14, doubled=True, bright=1.12)
    play_hybrid_tune(mix, b, beat, 32, 0.44, 0.14, doubled=True, bright=1.14)
    play_hybrid_tune(mix, c, beat, 64, 0.44, 0.14, doubled=True, bright=1.14)
    play_hybrid_tune(mix, b, beat, 96, 0.46, 0.14, doubled=True, bright=1.16)
    save("night", level([mix.render(45.0)], 0.86)[0], quality=4)


def victory() -> None:
    """勝利：D 大調的耀眼銅管凱旋號角×電子軍鼓與璀璨琶音。"""
    beat = 60 / 128
    mix = Mix(9.0, False)
    strum(mix, "D", 0.0, 0.48, 0.018, 2.8)
    mix.add(synth_bass(hz("D2"), 2.4 * beat, 0.95), 0.0, 0.50, -0.08, 0.12)
    mix.add(synth_bass(hz("G2"), 1.6 * beat, 0.92), 3.0 * beat, 0.46, -0.08, 0.12)
    mix.add(synth_bass(hz("D2"), 5.0 * beat, 1.02), 5.0 * beat, 0.56, -0.08, 0.14)
    mix.add(synth_stab("D", 0.25, 1.15), 5.0 * beat, 0.34, 0.28, 0.26)
    play_hybrid_tune(mix, ["A4:.5 D5:.5 F#5:.5 A5:1.5", "B5:.5 A5:.5 G5:.5 A5:.5", "D6:5"], beat, 0, 0.50, 0.12, doubled=True, bright=1.12)
    strum(mix, "G", 3 * beat, 0.44, 0.016, 2.2)
    strum(mix, "D", 5 * beat, 0.62, 0.025, 4.5)
    strum(mix, "D", 5 * beat + 0.45, 0.34, 0.018, 4.0, 0.3, up=True)
    for at, gain in ((0.0, 0.65), (1.5 * beat, 0.48), (3 * beat, 0.58), (5 * beat, 0.78)):
        mix.add(e_drum("kick"), at, gain, 0.0, 0.10)
        mix.add(drum("dum"), at, gain * 0.45, 0.0, 0.22)
    for at in (2.0 * beat, 4.0 * beat, 5.0 * beat):
        mix.add(e_drum("snare"), at, 0.52, 0.05, 0.20)
        mix.add(e_drum("clap"), at + 0.003, 0.34, -0.15, 0.24)
    for i, note_n in enumerate(["D5", "F#5", "A5", "D6", "F#6", "A5", "D6"]):
        mix.add(synth_arp(hz(note_n), beat * 0.65, 1.18), 5.0 * beat + i * beat * 0.28, 0.18, -0.35 + i * 0.11, 0.28)
    for j in range(18):
        mix.add(drum("shake"), 5 * beat + j * 0.055, 0.08 + 0.22 * np.sin(np.pi * j / 18), 0.4, 0.28)
    audio = mix.render(45.0)
    audio[-SR:] *= np.linspace(1, 0, SR)[:, None]
    save("victory", level([audio], 0.88)[0], quality=4)


def defeat() -> None:
    """敗北：D 小調輓歌，大鐘、魯特琴、木笛與沉厚暖色低音合成鋪底。"""
    beat = 60 / 66
    mix = Mix(10.5, False)
    mix.add(bell(146.83, 6.0), 0.0, 0.50, -0.2, 0.5)
    for bass_n, at_b, dur_b, gain in (("D2", 0.0, 1.9, 0.34), ("Bb2", 2.0, 0.95, 0.28), ("A2", 3.0, 0.95, 0.30), ("D2", 4.0, 4.8, 0.38)):
        mix.add(synth_bass(hz(bass_n), dur_b * beat, 0.62), at_b * beat, gain, -0.08, 0.26)
    mix.add(e_drum("kick"), 0.0, 0.32, 0.0, 0.18)
    mix.add(e_drum("kick"), 4.0 * beat, 0.36, 0.0, 0.20)
    for i, name in enumerate(["D2", "A2", "D3", "F3"]):
        mix.add(pluck(hz(name), 3.5, 0.8), i * beat / 2, 0.50, -0.2, 0.35)
    play_tune(mix, ["A4:1.5 G4:.5 F4:1 E4:1", "D4:4"], beat, 0, 0.46, 0.16)
    play_hybrid_tune(mix, ["A4:1.5 G4:.5 F4:1 E4:1", "D4:4"], beat, 0, 0.18, -0.12, doubled=False, bright=0.58)
    for i, name in enumerate(["Bb2", "F3", "Bb3"]):
        mix.add(pluck(hz(name), 3.0, 0.8), 2 * beat + i * 0.03, 0.38, -0.2, 0.35)
    for i, name in enumerate(["A2", "E3", "A3", "C#4"]):
        mix.add(pluck(hz(name), 3.0, 0.8), 3 * beat + i * 0.03, 0.38, -0.2, 0.35)
    for i, name in enumerate(["D2", "A2", "D3"]):
        mix.add(pluck(hz(name), 5.0, 0.75), 4 * beat + i * 0.05, 0.55, -0.2, 0.4)
    audio = mix.render(45.0)
    audio[-SR:] *= np.linspace(1, 0, SR)[:, None]
    save("defeat", level([audio], 0.82)[0], quality=4)


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
    # 治癒豎琴清音：輕撥 D 大調上行分散和弦，不帶人聲。
    mix = Mix(0.95, False)
    for i, (note, gain, pan) in enumerate((("D5", 0.45, -0.15), ("F#5", 0.52, 0.0), ("A5", 0.60, 0.12), ("D6", 0.68, 0.05))):
        mix.add(pluck(hz(note), 0.75, 0.75 + 0.05 * i), i * 0.055, gain, pan, 0.28)
    heal_audio = mix.render()
    fade = int(0.18 * SR)
    heal_audio[-fade:] *= np.linspace(1, 0, fade)[:, None]
    save("heal_chime", level([heal_audio], 0.72)[0], "audio")


def musket() -> None:
    """火繩槍：火藥爆開的一聲脆響、槍管的低沉回音，再一點硝煙的嘶聲。"""
    r = np.random.default_rng(1622)
    n = int(SR * 0.7)
    t = np.arange(n) / SR
    crack = band(r.standard_normal(n), 900, 9000) * np.exp(-t / 0.012) * 1.2
    boom = np.sin(2 * np.pi * (70 + 90 * np.exp(-t / 0.03)) * t) * np.exp(-t / 0.09) * 0.9
    body = band(r.standard_normal(n), 150, 1200) * np.exp(-t / 0.05) * 0.7
    hiss = band(r.standard_normal(n), 2500, 8000) * np.exp(-t / 0.25) * 0.06
    shot = (crack + boom + body + hiss) * np.minimum(t / 0.0007, 1.0)
    mix = Mix(0.7, False)
    mix.add(shot, 0.0, 1.0, 0.0, 0.35)
    audio = mix.render()
    audio[-int(0.1 * SR):] *= np.linspace(1, 0, int(0.1 * SR))[:, None]
    save("musket", level([audio], 0.9)[0], "audio")


PREVIEW_NAMES = {
    "normal": "normal",
    "magic": "magic",
    "dark": "dark",
    "beast": "beast",
    "conveyor": "conveyor_補給傳送帶",
    "charge": "charge_五路衝鋒",
    "duel": "duel_鐵血交鋒",
    "crimson": "crimson_赤旗總攻",
}


def previews(*names: str) -> None:
    """Export 90-second stereo MP3 previews (from battle stems) into film/音樂試聽/."""
    out_dir = ROOT.parent / "film" / "音樂試聽"
    out_dir.mkdir(parents=True, exist_ok=True)
    targets = names or tuple(PREVIEW_NAMES.keys())
    music_dir = ROOT / "assets" / "music"
    for key in targets:
        stem_names = [music_dir / f"battle_{key}_{l}.ogg" for l in ("lute", "drums", "tune", "tension")]
        for sp in stem_names:
            if not sp.exists():
                raise FileNotFoundError(f"Missing stem for preview: {sp}")
        out_mp3 = out_dir / f"{PREVIEW_NAMES.get(key, key)}.mp3"
        filt = (
            "[1:a]volume='if(lt(t,20),0.90,1.0)':eval=frame[d];"
            "[2:a]volume='if(lt(t,20),0.92,1.0)':eval=frame[m];"
            "[3:a]volume='if(lt(t,20),0.0,if(lt(t,45),0.45,1.0))':eval=frame[ten];"
            "[0:a][d][m][ten]amix=inputs=4:normalize=0:duration=first,"
            "alimiter=limit=0.95,"
            "afade=t=in:st=0:d=0.08,"
            "afade=t=out:st=88:d=2[out]"
        )
        cmd = [
            "ffmpeg", "-y", "-loglevel", "error",
            "-stream_loop", "-1", "-i", str(stem_names[0]),
            "-stream_loop", "-1", "-i", str(stem_names[1]),
            "-stream_loop", "-1", "-i", str(stem_names[2]),
            "-stream_loop", "-1", "-i", str(stem_names[3]),
            "-filter_complex", filt, "-map", "[out]",
            "-t", "90", "-ar", "44100", "-ac", "2", "-c:a", "libmp3lame", "-b:a", "192k",
            str(out_mp3),
        ]
        subprocess.run(cmd, check=True)
        print(f"preview -> {out_mp3} ({out_mp3.stat().st_size // 1024} KB)")


PIECES = {"musket": musket, "menu": menu, "battle": battle, "previews": previews, "night": night, "victory": victory, "defeat": defeat, "extras": extras}

if __name__ == "__main__":
    for name in (sys.argv[1:] or list(PIECES)):
        piece, _, arg = name.partition(":")
        PIECES[piece](*([arg] if arg else []))
