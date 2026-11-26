"""Synthesises the game's music and a few extra sounds. Original work, released CC0 with the game.

A medieval consort, acoustic timbres only (2026-11-24 rewrite: the 11-23 synth-brass / electronic-drum
themes did not fit the illuminated-manuscript look). Plucked: lute, harp. Bowed: vielle (fiddle),
hurdy-gurdy (melody, drones and its buzzing bridge), a bass fiddle. Blown: recorder, shawm, crumhorn,
natural trumpet, portative organ, a few monks singing. Struck: tabor with snare, frame and war drums,
nakers, tambourine, finger cymbals, hand bells and a church bell. In a stone hall (the dark theme and
the lament in a cathedral). Melodies are in church modes. Every run makes identical files (fixed seeds).

    python tools/make_music.py            # everything
    python tools/make_music.py menu night # only these pieces

Needs numpy, scipy and ffmpeg. Output: assets/music/*.ogg, assets/audio/{bell,heal_chime,ui_tick,ui_tock,musket}.ogg
The battle music is one theme per mood (normal, magic, dark, beast, conveyor, charge, duel, crimson;
music_mood.gd picks one per match), each four loops of the same length that play together
(music_player.gd raises the tension loop whenever the battle turns dangerous):
battle_<theme>_lute (accompaniment), _drums, _tune and _tension.
    python tools/make_music.py battle:dark  # one theme only
    python tools/make_music.py previews     # 90-second mixes into ../film/音樂試聽/
"""
import pathlib, subprocess, sys, wave, zlib
import numpy as np
from scipy.signal import butter, fftconvolve, iirpeak, lfilter, sosfilt

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



# ---- the rest of the consort (2026-11-24) ----------------------------------------------------
def _env(t: np.ndarray, att: float, dur: float, rel: float) -> np.ndarray:
    """Smooth rise over `att`, held to `dur`, then a release of `rel` seconds."""
    rise = np.sin(np.clip(t / max(att, 1e-4), 0, 1) * np.pi / 2) ** 2
    fall = np.clip((dur + rel - t) / rel, 0, 1) ** 1.5
    return rise * fall


def _wander(n: int, rate: float, r) -> np.ndarray:
    """Slow random drift (about `rate` turns a second), -1..1-ish."""
    pts = r.standard_normal(int(n / SR * rate) + 3)
    return np.interp(np.arange(n) / SR * rate, np.arange(len(pts)), pts)


def _local(*key) -> np.random.Generator:
    """A generator seeded from the note itself, so a cached sound is the same whichever piece made it first."""
    return np.random.default_rng(zlib.crc32(repr(key).encode()))


def _peaks(fk: np.ndarray, peaks) -> np.ndarray:
    """Body or bore resonances as bumps on a log-frequency axis: (centre Hz, height, width in octaves)."""
    return sum(a * np.exp(-0.5 * (np.log2(fk / f0) / w) ** 2) for f0, a, w in peaks)


BOWED = {
    # vielle: the medieval fiddle; gurdy: the hurdy-gurdy's wheel-bowed melody and drone strings
    # (steadier, brighter, no vibrato); drone: the gurdy's drone strings, darker; bass: a large bowed instrument.
    "vielle": dict(peaks=((280, 1.0, .4), (560, .5, .3), (1150, .75, .35), (2600, .4, .35)), tilt=1.15, vib=.0042, att=.07, rel=.12, noise=.02, top=4400),
    "gurdy": dict(peaks=((420, .7, .35), (1250, 1.0, .3), (2900, .7, .35)), tilt=.9, vib=.0006, att=.035, rel=.08, noise=.05, top=7500),
    "drone": dict(peaks=((300, 1.0, .4), (900, .7, .35), (2200, .3, .4)), tilt=1.0, vib=.0005, att=.05, rel=.1, noise=.015, top=4000),
    "bass": dict(peaks=((170, 1.0, .45), (400, .6, .35), (900, .35, .4)), tilt=1.05, vib=.003, att=.09, rel=.15, noise=.025, top=3800),
}


def body_ir(kind: str) -> np.ndarray:
    """The wooden box of a bowed instrument: a dozen narrow resonances at fixed places. Notes with
    vibrato sweep their partials across them, so the tone shimmers the way a real fiddle's does."""
    key = ("body", kind)
    if key in _cache:
        return _cache[key]
    r = np.random.default_rng(zlib.crc32(kind.encode()))
    low, high = {"vielle": (230, 4800), "gurdy": (300, 5500), "drone": (200, 3000), "bass": (90, 2000)}[kind]
    impulse = np.zeros(int(0.08 * SR))
    impulse[0] = 1.0
    ir = 0.35 * impulse
    for fc in np.exp(r.uniform(np.log(low), np.log(high), 12)):
        b, a = iirpeak(fc, r.uniform(6, 14), fs=SR)
        ir = ir + r.uniform(.4, 1.0) * lfilter(b, a, impulse) * 3.0
    ir *= np.linspace(1, 0, len(ir)) ** 2
    _cache[key] = ir
    return ir


def bowed(freq: float, dur: float, kind: str = "vielle", att: float = None) -> np.ndarray:
    """A bowed string: sawtooth-like partials shaped by the body, vibrato, bow hiss and a scratch on the attack."""
    key = ("bowed", round(freq, 2), round(dur, 3), kind, att)
    if key in _cache:
        return _cache[key]
    p = BOWED[kind]
    att = p["att"] if att is None else att
    rel = p["rel"]
    n = int(SR * (dur + rel))
    t = np.arange(n) / SR
    r = _local(key)
    ks = np.arange(1, int(min(40, p["top"] * 1.6 / freq)) + 1)
    fk = ks * freq
    amps = (0.3 + _peaks(fk, p["peaks"])) / ks ** p["tilt"] / (1 + (fk / p["top"]) ** 4)
    vib = p["vib"] * np.clip((t - 0.2) / 0.35, 0, 1) * np.sin(2 * np.pi * r.uniform(5.0, 5.8) * t + r.uniform(0, 6.3))
    vib = vib + 0.0011 * _wander(n, 3.0, r)
    phase = 2 * np.pi * freq * np.cumsum(1 + vib) / SR
    sig = np.zeros(n)
    for k, a, ph in zip(ks, amps, r.uniform(0, 2 * np.pi, len(ks))):
        sig += a * np.sin(k * phase + ph)
    sig = fftconvolve(sig, body_ir(kind))[:n]
    sig /= np.abs(sig).max() + 1e-9
    sig *= 1 + 0.035 * _wander(n, 9.0, r)  # bow pressure is never perfectly even
    env = _env(t, att, dur, rel)
    if dur > 0.6:
        env *= 0.86 + 0.14 * np.sin(np.pi * np.clip(t / dur, 0, 1))  # long notes swell and relax
    hiss = band(r.standard_normal(n), 2500, 8000) * p["noise"]
    scratch = band(r.standard_normal(n), 1200, 5000) * np.exp(-t / 0.03) * 0.22 * min(1.0, 0.04 / att)
    out = (sig + hiss) * env + scratch * np.minimum(t / 0.003, 1)
    out *= 0.42 / (np.abs(out).max() + 1e-9)
    _cache[key] = out
    return out


def reed(freq: float, dur: float, kind: str = "shawm") -> np.ndarray:
    """Double reeds: the shawm (loud, nasal, the street-band trumpet of its day) or the capped crumhorn (buzzy, odd partials)."""
    key = ("reed", round(freq, 2), round(dur, 3), kind)
    if key in _cache:
        return _cache[key]
    rel = 0.06
    n = int(SR * (dur + rel))
    t = np.arange(n) / SR
    r = _local(key)
    top = 7000 if kind == "shawm" else 3500
    ks = np.arange(1, int(min(36, top * 1.5 / freq)) + 1)
    fk = ks * freq
    if kind == "shawm":
        amps = (0.35 + _peaks(fk, ((1150, 1.3, .4), (2700, .8, .35)))) / ks ** 0.5
    else:
        amps = np.where(ks % 2 == 1, 1.0, 0.22) * (0.5 + _peaks(fk, ((950, .6, .5),))) / ks ** 0.9
    amps /= 1 + (fk / top) ** 4
    vib = 0.0022 * np.clip((t - 0.22) / 0.3, 0, 1) * np.sin(2 * np.pi * 5.2 * t + r.uniform(0, 6.3))
    scoop = -0.014 * np.exp(-t / 0.025)  # the player lips up into the note
    phase = 2 * np.pi * freq * np.cumsum(1 + vib + scoop + 0.0008 * _wander(n, 2.5, r)) / SR
    sig = np.zeros(n)
    for k, a, ph in zip(ks, amps, r.uniform(0, 2 * np.pi, len(ks))):
        sig += a * np.sin(k * phase + ph)
    sig /= np.abs(sig).max() + 1e-9
    breath = band(r.standard_normal(n), 2000, 7000) * 0.03
    out = (sig + breath) * _env(t, 0.018, dur, rel)
    out *= 0.40 / (np.abs(out).max() + 1e-9)
    _cache[key] = out
    return out


def trumpet(freq: float, dur: float) -> np.ndarray:
    """A valveless natural trumpet: bright brassy blare on the attack, rounder as the note settles."""
    key = ("trumpet", round(freq, 2), round(dur, 3))
    if key in _cache:
        return _cache[key]
    rel = 0.07
    n = int(SR * (dur + rel))
    t = np.arange(n) / SR
    r = _local(key)
    ks = np.arange(1, int(min(24, 11000 / freq)) + 1)
    blare = 0.45 + 0.55 * np.exp(-t / 0.09)
    if dur > 0.7:
        blare = blare + 0.18 * np.clip((t - 0.3) / max(dur - 0.3, 0.1), 0, 1)
    vib = 0.0025 * np.clip((t - 0.25) / 0.3, 0, 1) * np.sin(2 * np.pi * 5.0 * t + r.uniform(0, 6.3))
    scoop = -0.02 * np.exp(-t / 0.02)
    phase = 2 * np.pi * freq * np.cumsum(1 + vib + scoop) / SR
    sig = np.zeros(n)
    for k, ph in zip(ks, r.uniform(0, 2 * np.pi, len(ks))):
        lift = 1 + 0.6 * np.exp(-0.5 * (np.log2(k * freq / 1300) / 0.5) ** 2)
        sig += lift * np.exp(-(k - 1) / (1.1 + 4.5 * blare)) * np.sin(k * phase + ph)
    sig /= np.abs(sig).max() + 1e-9
    lip = band(r.standard_normal(n), 600, 3000) * np.exp(-t / 0.015) * 0.18
    out = (sig * _env(t, 0.012, dur, rel)) + lip
    out *= 0.42 / (np.abs(out).max() + 1e-9)
    _cache[key] = out
    return out


def organ(freq: float, dur: float) -> np.ndarray:
    """A portative organ: open flue pipes (8', 4' and a quint), a chiff as each pipe speaks."""
    key = ("organ", round(freq, 2), round(dur, 3))
    if key in _cache:
        return _cache[key]
    rel = 0.06
    n = int(SR * (dur + rel))
    t = np.arange(n) / SR
    r = _local(key)
    sig = np.zeros(n)
    for mult, partials in ((1.0, (1.0, .22, .09, .05)), (2.0012, (.36, .08)), (2.9985, (.12,))):
        for j, a in enumerate(partials):
            f = freq * mult * (j + 1)
            if f < 12000:
                sig += a * np.sin(2 * np.pi * f * t + r.uniform(0, 6.3))
    sig *= 1 + 0.012 * _wander(n, 4.0, r)  # the bellows
    sig /= np.abs(sig).max() + 1e-9
    centre = min(freq * 3, 6000)
    chiff = band(r.standard_normal(n), centre * 0.7, centre * 1.4) * np.exp(-t / 0.025) * 0.35
    out = sig * _env(t, 0.025, dur, rel) + chiff * np.minimum(t / 0.002, 1)
    out *= 0.40 / (np.abs(out).max() + 1e-9)
    _cache[key] = out
    return out


def harp(freq: float, ring: float = 2.5) -> np.ndarray:
    """A gut-strung medieval harp: plucked mid-string with the fingertip, rounder and longer than the lute."""
    key = ("harp", round(freq, 2), round(ring, 2))
    if key in _cache:
        return _cache[key]
    n = int(SR * ring)
    t = np.arange(n) / SR
    r = _local(key)
    out = np.zeros(n)
    tau1 = 2.8 * (220.0 / freq) ** 0.45
    for k in range(1, int(min(30, 9000 / freq)) + 1):
        fk = k * freq * np.sqrt(1 + 0.00004 * k * k)
        out += np.sin(np.pi * k * 0.28) / k ** 1.15 * np.exp(-t / (tau1 / (1 + 0.012 * k * k))) * np.sin(2 * np.pi * fk * t + r.uniform(0, 0.5))
    attack = int(0.004 * SR)
    out[:attack] += band(r.standard_normal(attack), 800, 3500) * 0.12 * np.linspace(1, 0, attack)
    out *= np.minimum(t / 0.0012, 1.0)
    out[-int(0.04 * SR):] *= np.linspace(1, 0, int(0.04 * SR))
    out = 0.6 * out + 0.4 * band(out, low=110, order=1)
    out *= 0.95 / (np.abs(out).max() + 1e-9)
    _cache[key] = out
    return out


VOWELS = {  # men's voices: (formant Hz, height, bandwidth Hz)
    "a": ((650, 1.0, 90), (1080, .45, 100), (2650, .28, 140), (2900, .2, 150)),
    "o": ((420, 1.0, 80), (800, .4, 90), (2600, .12, 140)),
    "u": ((330, 1.0, 70), (640, .25, 80), (2500, .08, 140)),
}


def choir(freq: float, dur: float, vowel: str = "o", voices: int = 4) -> np.ndarray:
    """A few monks singing one vowel: each voice its own pitch wobble, the vowel's formants shaping all of them."""
    key = ("choir", round(freq, 2), round(dur, 3), vowel, voices)
    if key in _cache:
        return _cache[key]
    rel, att = 0.3, 0.22
    n = int(SR * (dur + rel))
    t = np.arange(n) / SR
    r = _local(key)
    out = np.zeros(n)
    for v in range(voices):
        f0 = freq * 2 ** ((v - (voices - 1) / 2) * 5 / 1200)
        vib = 0.005 * np.clip((t - 0.25) / 0.4, 0, 1) * np.sin(2 * np.pi * r.uniform(4.6, 5.6) * t + r.uniform(0, 6.3)) + 0.0018 * _wander(n, 2.0, r)
        phase = 2 * np.pi * f0 * np.cumsum(1 + vib) / SR
        ks = np.arange(1, int(min(60, 5000 / f0)) + 1)
        fk = ks * f0
        amps = sum(a / (1 + ((fk - F) / bw) ** 2) for F, a, bw in VOWELS[vowel]) / ks ** 0.8 + 0.002
        start = int(r.uniform(0, 0.05) * SR)  # singers never breathe in quite together
        for k, a, ph in zip(ks, amps, r.uniform(0, 2 * np.pi, len(ks))):
            out[start:] += a * np.sin(k * phase[:n - start] + ph)
    out /= np.abs(out).max() + 1e-9
    out += band(r.standard_normal(n), 400, 3000) * 0.012
    out *= _env(t, att, dur, rel)
    out *= 0.40 / (np.abs(out).max() + 1e-9)
    _cache[key] = out
    return out


def handbell(freq: float, ring: float = 3.0) -> np.ndarray:
    """A small bronze hand bell."""
    key = ("handbell", round(freq, 2), ring)
    if key in _cache:
        return _cache[key]
    n = int(SR * ring)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, a, tau in ((1.0, 1.0, 1.6), (2.0, .45, 1.0), (2.76, .3, .7), (5.4, .16, .3), (8.9, .08, .15)):
        if freq * ratio < 15000:
            out += a * np.exp(-t / tau) * np.sin(2 * np.pi * freq * ratio * t + ratio)
    out *= np.minimum(t / 0.0015, 1.0)
    out[-2000:] *= np.linspace(1, 0, 2000)
    out *= 0.8 / (np.abs(out).max() + 1e-9)
    _cache[key] = out
    return out


def buzz(freq: float, dur: float = 0.22) -> np.ndarray:
    """The hurdy-gurdy's 'dog': a loose bridge that rattles when the player jerks the wheel."""
    key = ("buzz", round(freq, 2), round(dur, 3))
    if key in _cache:
        return _cache[key]
    n = int(SR * (dur + 0.03))
    t = np.arange(n) / SR
    ks = np.arange(1, int(min(70, 11000 / freq)) + 1)
    sig = np.zeros(n)
    for k in ks:
        sig += (1 - np.exp(-k * freq / 1800)) * np.sin(2 * np.pi * k * freq * t + 0.3 * k)
    sig /= np.abs(sig).max() + 1e-9
    env = np.minimum(t / 0.004, 1) * np.exp(-t / (dur * 0.7)) * np.clip((dur + 0.03 - t) / 0.03, 0, 1)
    out = band(sig * env, 500, 9000)
    out *= 0.12 / (np.sqrt((out ** 2).mean()) + 1e-9)  # by loudness: a pulse train's peaks say little
    _cache[key] = out
    return out


def _jingles(n: int, r, count: int, spread: float) -> np.ndarray:
    """Loose brass discs knocking together: every disc its own inharmonic ring, all of them short."""
    t = np.arange(n) / SR
    out = np.zeros(n)
    for _ in range(count):
        off = int(r.uniform(0, spread) * SR)
        tt = t[:n - off]
        for f in r.uniform(2600, 11500, 5):
            out[off:] += r.uniform(.3, 1) * np.sin(2 * np.pi * f * tt + r.uniform(0, 6.3)) * np.exp(-tt / r.uniform(.02, .07))
    return out * 0.5 + band(r.standard_normal(n), 4500, 12000) * np.exp(-t / 0.025) * 1.2


def perc(kind: str) -> np.ndarray:
    """tabor (a drum with a gut snare across the skin), naker_hi/naker_lo (a pair of small kettle drums),
    tamb (tambourine struck), jingle (tambourine shaken), zill (finger cymbals)."""
    key = ("perc", kind)
    if key in _cache:
        return _cache[key]
    r = np.random.default_rng(900 + sum(ord(c) for c in kind))
    kind = kind.partition("#")[0]  # "jingle#2": another tambourine stroke, so a run of them never repeats exactly
    if kind == "tabor":
        n = int(SR * 0.45)
        t = np.arange(n) / SR
        f = 150 + 60 * np.exp(-t / 0.015)
        ph = 2 * np.pi * np.cumsum(f) / SR
        body = np.sin(ph) * np.exp(-t / 0.09) + 0.4 * np.sin(1.6 * ph) * np.exp(-t / 0.05)
        snare = band(r.standard_normal(n), 1800, 7500) * np.exp(-t / 0.1) * 0.6 + band(r.standard_normal(n), 700, 1800) * np.exp(-t / 0.045) * 0.3
        out = body * 0.7 + snare
    elif kind.startswith("naker"):
        f0 = 205.0 if kind == "naker_hi" else 150.0
        n = int(SR * 0.6)
        t = np.arange(n) / SR
        bend = 1 + 0.05 * np.exp(-t / 0.02)
        out = sum(a * np.exp(-t / d) * np.sin(2 * np.pi * np.cumsum(f0 * m * bend) / SR) for m, a, d in ((1, 1, .32), (1.5, .5, .22), (1.99, .35, .16), (2.44, .2, .11), (2.98, .12, .08)))
        out += band(r.standard_normal(n), 2000, 6000) * np.exp(-t / 0.004) * 0.6
    elif kind in ("tamb", "jingle"):
        n = int(SR * 0.35)
        t = np.arange(n) / SR
        out = _jingles(n, r, 7 if kind == "tamb" else 5, 0.012 if kind == "tamb" else 0.04) * (1.0 if kind == "tamb" else 0.6)
        if kind == "tamb":
            out += np.sin(2 * np.pi * 230 * t) * np.exp(-t / 0.03) * 1.2
    else:  # zill
        n = int(SR * 1.6)
        t = np.arange(n) / SR
        out = sum(a * np.exp(-t / d) * (np.sin(2 * np.pi * f * t) + np.sin(2 * np.pi * f * 1.004 * t + 1)) for f, a, d in ((2780, 1, 1.2), (3910, .7, .9), (6620, .5, .6), (8240, .35, .45), (10230, .2, .3)))
        out += band(r.standard_normal(n), 4000, 12000) * np.exp(-t / 0.003) * 0.8
    out *= np.minimum(np.arange(len(out)) / 30.0, 1.0)
    out[-200:] *= np.linspace(1, 0, 200)
    out *= 1.0 / (np.abs(out).max() + 1e-9)
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



ROOM = room()  # a small stone hall
CATHEDRAL = room(3.6, 11)  # the nave, for the dark theme and the lament


class Mix:
    """A stereo timeline. With loop=True events are laid twice and the second pass is kept, so
    ringing strings and the room's tail wrap round the loop point."""

    def __init__(self, seconds: float, loop: bool, ir: np.ndarray = None):
        self.length = int(round(seconds * SR))
        self.loop = loop
        self.ir = ROOM if ir is None else ir
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

    def render(self, low_cut: float = 55.0, air: float = 0.3) -> np.ndarray:
        out = self.dry.copy()
        for ch in range(2):
            out[:, ch] += fftconvolve(self.wet[:, ch], self.ir[:, ch])[:self.total] * 0.5
        out = band(out, low=low_cut)
        out += air * band(out, low=2600, order=1)  # lifts the top octaves a little
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



# ---- playing a written line ---------------------------------------------------------------------
def midi(name: str) -> int:
    return SEMITONE[name[:-1]] + 12 * (int(name[-1]) + 1)


def lead_note(inst: str, f: float, sec: float):
    """One melody note on `inst`, as (sound, reverb send)."""
    if inst == "recorder":
        return recorder(f, sec * 0.94), 0.32
    if inst == "vielle":
        return bowed(f, sec * 0.99 + 0.02, "vielle"), 0.30
    if inst == "gurdy":
        return bowed(f, sec * 0.97, "gurdy", att=0.02), 0.28
    if inst in ("shawm", "crumhorn"):
        return reed(f, sec * 0.9, inst), 0.26
    if inst == "trumpet":
        return trumpet(f, sec * 0.86), 0.30
    if inst == "organ":
        return organ(f, sec * 0.96), 0.36
    if inst.startswith("choir"):
        return choir(f, sec * 1.02 + 0.05, inst.partition(":")[2] or "o"), 0.45
    if inst == "lute":
        return pluck(f, min(2.0, sec + 0.6), 1.15), 0.24
    if inst == "harp":
        return harp(f, min(3.0, sec + 1.2)), 0.36
    return handbell(f, 2.5), 0.40  # "bells"


def play_line(mix: Mix, inst: str, bars: list, beat: float, start_beat: float, gain: float, pan: float, octave: int = 0, min_beats: float = 0.0) -> None:
    """Bars of 'D5:1 A4:.5 R:1' on one instrument; notes shorter than `min_beats` are left to the others
    (bells and the choir only take the long notes)."""
    at = start_beat
    for bar in bars:
        first = True
        for pitch, beats in line(bar):
            if pitch is not None and beats >= min_beats - 1e-9:
                sound, send = lead_note(inst, hz(pitch) * 2 ** octave, beats * beat)
                accent = 1.08 if first else (0.93 if (at % 1) > 1e-6 else 1.0)
                mix.add(sound, at * beat + human(0.004), gain * accent * float(rng.uniform(0.94, 1.04)), pan, send)
            first = False
            at += beats


def ornament(bar: str, th: dict, seed: int) -> str:
    """A player's variation on a written bar: turns on long notes, passing notes across thirds."""
    names = {SEMITONE[s]: s for s in th["scale"].split()}
    pcs = sorted(names)
    u = th.get("orn_unit", 0.25)
    r = np.random.default_rng(seed)
    notes = line(bar)
    out = []

    def spell(m: int) -> str:
        return f"{names[m % 12]}{m // 12 - 1}"

    for i, (p, b) in enumerate(notes):
        nxt = notes[i + 1][0] if i + 1 < len(notes) else None
        if p is None or b < 4 * u - 1e-9 or r.random() > 0.6:
            out.append((p, b))
            continue
        m = midi(p)
        if nxt is not None and 3 <= abs(midi(nxt) - m) <= 4:
            lo, hi = sorted((m, midi(nxt)))
            between = [x for x in range(lo + 1, hi) if x % 12 in pcs and x - lo <= 2 and hi - x <= 2]  # no augmented seconds
            if between:
                out += [(p, b - 2 * u), (spell(between[0]), 2 * u)]
                continue
        up = next(x for x in range(m + 1, m + 13) if x % 12 in pcs)
        out += [(p, b - 2 * u), (spell(up), u), (p, u)]
    return " ".join(f"{p or 'R'}:{b:g}" for p, b in out)


def strong_tones(chord: str) -> tuple:
    bass, tones = CHORDS[chord]
    return bass, tones, tones[-3:]


# ---- accompaniment (the always-on "lute" layer) -------------------------------------------------
def quarter_lute(mix: Mix, chord: str, t0: float, beat: float) -> None:
    bass, tones = CHORDS[chord]
    for pos, name, g, ring in ((0, bass, .58, 2.6), (1, tones[2], .3, 1.5), (2, tones[0], .45, 2.2), (3, tones[min(3, len(tones) - 1)], .3, 1.5)):
        mix.add(pluck(hz(name), ring, 1.0), t0 + pos * beat + human(), g * float(rng.uniform(.92, 1.05)), -.28 + .1 * pos, .26)


def base_march(mix, chord, t0, beat, bar, sec, energy, th):
    if energy == 0:
        quarter_lute(mix, chord, t0, beat)
    else:
        lute_bar(mix, "vamp", chord, t0, beat, sec)
    if energy >= 2 and bar % 2 == 1:
        strum(mix, chord, t0 + 3.5 * beat, .14, .009, .6, -.32, up=True)


def base_harp(mix, chord, t0, beat, bar, sec, energy, th):
    bass, tones = CHORDS[chord]
    pool = [hz(x) for x in tones] + [hz(x) * 2 for x in tones[1:3]]
    seq = pool + pool[-2:0:-1]
    step = .25 if energy else .5
    for i in range(int(round(4 / step))):
        idx = i % len(seq)
        mix.add(harp(seq[idx], 2.2), t0 + i * step * beat + human(.003), (.3 if i % 4 == 0 else .21) * float(rng.uniform(.9, 1.05)), -.4 + .8 * idx / len(seq), .38)
    mix.add(harp(hz(bass), 3.6), t0 + human(), .42, -.2, .3)
    mix.add(organ(hz(bass) * 2, 4 * beat * .98), t0, .10, .15, .4)
    mix.add(organ(hz(tones[0]) * 2, 4 * beat * .98), t0, .07, .22, .4)


def base_dirge(mix, chord, t0, beat, bar, sec, energy, th):
    bass, tones = CHORDS[chord]
    mix.add(pluck(hz(bass), 4.5, .7), t0 + human(), .58, -.2, .4)
    mix.add(pluck(hz(tones[0]), 3.5, .75), t0 + 2 * beat + human(), .36, -.05, .4)
    if energy >= 1:
        for i, name in enumerate(tones[1:4]):
            mix.add(pluck(hz(name), 2.2, .9), t0 + (2.5 + i * .5) * beat + human(), .2, .15 + i * .1, .45)
    if bar % 4 == 0:
        mix.add(bell(hz(th["bell"]), 6.0), t0, .2, .3, .55)


def base_riff(mix, chord, t0, beat, bar, sec, energy, th):
    lute_bar(mix, "riff", chord, t0, beat, sec)
    if energy >= 1:
        for pos in (0, 1.5, 3):
            mix.add(buzz(hz(th["drone"][0])), t0 + pos * beat + human(.002), .17 if pos == 0 else .12, .3, .2)


def base_jig(mix, chord, t0, beat, bar, sec, energy, th):  # 6/8, beat = an eighth
    bass, tones = CHORDS[chord]
    for pos in range(6):
        if pos in (0, 3):
            mix.add(pluck(hz(bass if pos == 0 else tones[0]), 1.8, .95), t0 + pos * beat + human(), .56 if pos == 0 else .44, -.3, .24)
        elif energy or pos in (2, 5):
            name = tones[1 + pos % 3] if len(tones) > 3 else tones[-1]
            mix.add(pluck(hz(name), 1.0, 1.1), t0 + pos * beat + human(), .27 * float(rng.uniform(.9, 1.06)), -.1 + .1 * (pos % 3), .24)
    if energy >= 2:
        mix.add(harp(hz(tones[-1]) * 2, 1.6), t0 + human(), .15, .42, .4)
        mix.add(harp(hz(tones[-2]) * 2, 1.6), t0 + 3 * beat + human(), .13, .42, .4)


def base_gallop(mix, chord, t0, beat, bar, sec, energy, th):  # 6/8 saltarello
    bass, tones = CHORDS[chord]
    for pos, name, g, ring in ((0, bass, .6, 1.6), (2, tones[2], .3, .9), (3, tones[0], .46, 1.4), (5, tones[3 % len(tones)], .3, .9)):
        mix.add(pluck(hz(name), ring, 1.0), t0 + pos * beat + human(), g * float(rng.uniform(.92, 1.05)), -.3 + .08 * pos, .24)
    if energy >= 1:
        strum(mix, chord, t0 + human(), .12, .008, .7, -.3)
    if energy >= 2:
        for pos in (0, 3):
            mix.add(buzz(hz(th["drone"][0]), .18), t0 + pos * beat, .14, .3, .2)


def base_chop(mix, chord, t0, beat, bar, sec, energy, th):
    bass, tones = CHORDS[chord]
    for pos in (0, 1.5, 3):
        mix.add(pluck(hz(bass), 1.4, .9), t0 + pos * beat + human(), .6 if pos == 0 else .45, -.3, .22)
        mix.add(pluck(hz(tones[0]), 1.2, .95), t0 + pos * beat + .012, .3, -.15, .22)
    for pos in ((.5, 1, 2, 2.5, 3.5) if energy else (1, 3)):
        for j, name in enumerate(tones[1:3]):
            mix.add(bowed(hz(name) * 2, .13, "vielle", att=.012), t0 + pos * beat + human(.003), .15, .2 + .1 * j, .25)


def base_epic(mix, chord, t0, beat, bar, sec, energy, th):
    bass = CHORDS[chord][0]
    if energy:
        lute_bar(mix, "vamp", chord, t0, beat, sec)
    else:
        quarter_lute(mix, chord, t0, beat)
    f = hz(bass) * (2 if hz(bass) < 80 else 1)
    for half in (0, 2):
        mix.add(bowed(f, 2 * beat * .95, "bass", att=.04), t0 + half * beat, .2, -.1, .3)
    if energy >= 1:
        for pos in (0, 2):
            mix.add(buzz(hz(th["drone"][0]) * 2), t0 + pos * beat + human(.002), .13, .3, .2)


# ---- percussion layer ---------------------------------------------------------------------------
def hit(mix: Mix, kind: str, at: float, gain: float, pan: float = 0.0, send: float = 0.2) -> None:
    if kind in ("tamb", "jingle"):
        kind += f"#{int(rng.integers(4))}"
    sound = drum(kind) if kind in ("dum", "tak", "war", "shake") else perc(kind)
    mix.add(sound, at + human(0.003), gain * float(rng.uniform(0.93, 1.05)), pan, send)


def roll(mix: Mix, kind: str, start: float, count: int, step: float, g0: float, g1: float, pan: float = 0.1) -> None:
    for j in range(count):
        hit(mix, kind, start + j * step, g0 + (g1 - g0) * j / max(1, count - 1), pan, .22)


def drums_march(mix, t0, beat, bar, sec, energy, th):
    fill = bar % 8 == 7
    hit(mix, "dum", t0, .6)
    hit(mix, "dum", t0 + 2 * beat, .48)
    hit(mix, "tabor", t0 + beat, .42, .12)
    if not fill:
        hit(mix, "tabor", t0 + 3 * beat, .42, .12)
    if energy >= 1:
        hit(mix, "dum", t0 + 2.5 * beat, .28)
        hit(mix, "tabor", t0 + 3.5 * beat, .13, .12)
        for i in range(8):
            hit(mix, "tamb" if i in (2, 6) else "jingle", t0 + i * beat / 2, .26 if i in (2, 6) else .17, .45)
    else:
        for i in range(4):
            hit(mix, "jingle", t0 + i * beat, .18, .45)
    if fill:
        roll(mix, "tabor", t0 + 2 * beat, 8, beat / 4, .1, .4)


def drums_magic(mix, t0, beat, bar, sec, energy, th):
    hit(mix, "dum", t0, .45, 0, .35)
    if energy >= 1:
        hit(mix, "dum", t0 + 2.5 * beat, .25, 0, .35)
        for i in range(8):
            hit(mix, "jingle", t0 + i * beat / 2, .13 if i % 2 else .17, .45, .35)
    if energy >= 1 or bar % 2 == 0:
        for pos in (1, 3):
            hit(mix, "zill", t0 + pos * beat, .15, -.4, .45)
    if energy >= 2:
        hit(mix, "naker_lo", t0, .26, -.15)
        hit(mix, "naker_hi", t0 + 1.5 * beat, .2, .15)
        hit(mix, "naker_hi", t0 + 3.5 * beat, .2, .15)
    if bar % 8 == 7:
        roll(mix, "naker_hi", t0 + 2 * beat, 8, beat / 4, .08, .3, .15)


def drums_heartbeat(mix, t0, beat, bar, sec, energy, th):
    fill = bar % 8 == 7
    hit(mix, "war", t0, .6, 0, .35)
    hit(mix, "war", t0 + .5 * beat, .36, 0, .35)
    if energy >= 1 and not fill:
        hit(mix, "war", t0 + 2 * beat, .4, 0, .35)
        hit(mix, "war", t0 + 2.5 * beat, .24, 0, .35)
    if bar % 2 == 1:
        hit(mix, "tak", t0 + 3.5 * beat, .18, .3, .45)
    if bar % 4 == 2:
        hit(mix, "zill", t0, .08, -.45, .6)
    if fill:
        roll(mix, "war", t0 + 2 * beat, 4, beat / 2, .2, .5, 0)


def drums_tribal(mix, t0, beat, bar, sec, energy, th):
    for pos, g in ((0, .62), (1.5, .5), (3, .46)):
        hit(mix, "war", t0 + pos * beat, g, 0, .25)
    if energy >= 1:
        for pos in (1, 2.5):
            hit(mix, "dum", t0 + pos * beat, .3, -.12)
        for i, kind in enumerate(("naker_lo", "naker_hi", "naker_hi", "naker_lo", "naker_hi", "naker_hi", "naker_lo", "naker_hi")):
            hit(mix, kind, t0 + i * beat / 2, .22 if kind == "naker_lo" else .15, -.2 if kind == "naker_lo" else .2)
    if energy >= 2:
        hit(mix, "tabor", t0 + 2 * beat, .36, .1)
        for i in range(8):
            hit(mix, "tamb" if i in (0, 3, 6) else "jingle", t0 + i * beat / 2, .2 if i in (0, 3, 6) else .13, .45)
    if bar % 8 == 7:
        roll(mix, "tabor", t0 + 2 * beat, 8, beat / 4, .12, .42)


def drums_jig(mix, t0, beat, bar, sec, energy, th):
    fill = bar % 8 == 7
    hit(mix, "dum", t0, .55)
    hit(mix, "dum", t0 + 3 * beat, .4)
    hit(mix, "tabor" if energy else "tak", t0 + 2 * beat, .3, .12)
    if not fill:
        hit(mix, "tabor" if energy else "tak", t0 + 5 * beat, .3, .12)
    for i in range(6):
        hit(mix, "jingle", t0 + i * beat, .22 if i in (0, 3) else .13, .45)
    if energy >= 2:
        for pos in (1, 4):
            hit(mix, "naker_hi", t0 + pos * beat, .14, -.2)
    if fill:
        roll(mix, "tabor", t0 + 3 * beat, 6, beat / 2, .15, .42)


def drums_gallop(mix, t0, beat, bar, sec, energy, th):
    fill = bar % 8 == 7
    hit(mix, "war", t0, .55, 0, .25)
    hit(mix, "dum", t0 + 3 * beat, .42)
    for pos in (2, 5):
        if not (fill and pos == 5):
            hit(mix, "tabor" if energy else "tak", t0 + pos * beat, .34, .12)
    for pos in (0, 2, 3, 5):
        hit(mix, "tamb" if pos in (0, 3) else "jingle", t0 + pos * beat, .2, .45)
    if energy >= 2:
        for i in range(6):
            hit(mix, "naker_lo" if i % 3 == 0 else "naker_hi", t0 + i * beat, .14, -.2)
    if fill:
        roll(mix, "tabor", t0 + 3 * beat, 6, beat / 2, .15, .45)


def drums_duel(mix, t0, beat, bar, sec, energy, th):
    hit(mix, "dum", t0, .5)
    for i in range(8):
        low = i in (0, 3, 6)
        hit(mix, "naker_lo" if low else "naker_hi", t0 + i * beat / 2, .3 if low else .17, -.2 if low else .2)
    if energy >= 1:
        for pos in (1, 3):
            hit(mix, "tabor", t0 + pos * beat, .4, .1)
    if energy >= 2:
        for i in range(8):
            hit(mix, "jingle", t0 + i * beat / 2, .14, .45)
    if bar % 8 == 7:
        roll(mix, "tabor", t0 + 2 * beat, 8, beat / 4, .12, .42)


def drums_epic(mix, t0, beat, bar, sec, energy, th):
    fill = bar % 8 == 7
    hit(mix, "war", t0, .62, 0, .25)
    hit(mix, "war", t0 + 2 * beat, .5, 0, .25)
    hit(mix, "tabor", t0 + beat, .44, .1)
    if not fill:
        hit(mix, "tabor", t0 + 3 * beat, .44, .1)
        hit(mix, "tabor", t0 + 3.75 * beat, .18, .1)
    for i in range(8):
        hit(mix, "tamb" if i in (2, 6) else "jingle", t0 + i * beat / 2, .22 if i in (2, 6) else .14, .45)
    if energy >= 2:
        for i in (1, 3, 5, 7):
            hit(mix, "war", t0 + i * beat / 2, .2, 0, .25)
    if fill:
        roll(mix, "tabor", t0 + 2 * beat, 8, beat / 4, .12, .45)
        hit(mix, "war", t0 + 3.5 * beat, .45)


# ---- tension layer (raised when the battle turns dangerous or decisive) -------------------------
def tension_fanfare(mix, chord, t0, beat, bar, sec, energy, th):
    bass, tones, hi = strong_tones(chord)
    for pos, d, i in ((0, .75, 2), (.75, .25, 1), (1, 1, 0), (2, .75, 2), (2.75, .25, 1), (3, 1, 1)):
        mix.add(reed(hz(hi[i]), d * beat * .85, "shawm"), t0 + pos * beat + human(.003), .3 if d >= .75 else .24, .3, .25)
    for i in range(4):
        hit(mix, "war", t0 + i * beat, .5 if i == 0 else .32)
    for i in range(16):
        hit(mix, "jingle", t0 + i * beat / 4, .11 if i % 2 else .15, .45)
    if bar % 4 == 3:
        roll(mix, "tabor", t0 + 2 * beat, 8, beat / 4, .12, .4)


def tension_spark(mix, chord, t0, beat, bar, sec, energy, th):
    bass, tones = CHORDS[chord]
    pool = [hz(x) * 2 for x in tones[1:]]
    seq = pool[::-1] + pool[1:-1]
    for i in range(16):
        mix.add(harp(seq[i % len(seq)], 1.6), t0 + i * beat / 4 + human(.002), .2 if i % 4 == 0 else .14, .4 - .8 * (i % len(seq)) / len(seq), .4)
        hit(mix, "naker_hi", t0 + i * beat / 4, .17 if i % 4 == 0 else .07, .2)
    for pos in range(4):
        hit(mix, "zill", t0 + pos * beat, .1, -.4, .45)
    mix.add(organ(hz(tones[0]) * 4, 4 * beat * .98), t0, .08, -.2, .45)


def tension_dread(mix, chord, t0, beat, bar, sec, energy, th):
    bass, tones = CHORDS[chord]
    root = hz(bass) * (2 if hz(bass) < 100 else 1)
    for i in range(16):
        at = t0 + i * beat / 4
        mix.add(bowed(root, beat / 4 * .95, "vielle", att=.008), at + human(.002), .15 if i % 4 == 0 else .1, -.25, .3)
        mix.add(bowed(root * 1.5, beat / 4 * .95, "vielle", att=.008), at + human(.002), .08, .25, .3)
    for f in (root, root * 1.5, root * 2):
        mix.add(choir(f, 4 * beat, "a"), t0, .17, 0, .5)
    for i in range(8):
        hit(mix, "war", t0 + i * beat / 2, .5 if i == 0 else (.36 if i == 4 else .22), 0, .3)


def tension_horde(mix, chord, t0, beat, bar, sec, energy, th):
    bass, tones = CHORDS[chord]
    for i in range(8):
        accent = i in (0, 3, 6)
        mix.add(buzz(hz(th["drone"][0]), .16), t0 + i * beat / 2, .2 if accent else .11, .3, .2)
        hit(mix, "war", t0 + i * beat / 2, .5 if accent else .25, 0, .25)
    if bar % 2 == 0:
        root = hz(bass) * (2 if hz(bass) < 130 else 1)
        for pos, f, d in ((0, root, 1.3), (1.5, root * 1.5, 1.3), (3, root * 2, .9)):
            mix.add(trumpet(f, d * beat), t0 + pos * beat + human(.003), .32, -.25, .3)


def tension_reel(mix, chord, t0, beat, bar, sec, energy, th):  # 6/8
    bass, tones = CHORDS[chord]
    pool = [hz(x) * 2 for x in tones[1:4]] + [hz(tones[1]) * 4]
    seq = pool + pool[-2:0:-1]
    for i in range(6):
        mix.add(bowed(seq[(i + bar) % len(seq)], beat * .9, "vielle", att=.015), t0 + i * beat + human(.003), .34 if i in (0, 3) else .25, -.25, .28)
        hit(mix, "tabor", t0 + i * beat, .38 if i in (0, 3) else .17, .1)
    for pos in (0, 3):
        mix.add(reed(hz(tones[-1]), beat * 1.6, "shawm"), t0 + pos * beat, .3, .3, .25)
    hit(mix, "war", t0, .4, 0, .25)


def tension_charge(mix, chord, t0, beat, bar, sec, energy, th):  # 6/8
    bass, tones, hi = strong_tones(chord)
    for pos, d, i in ((0, 2, 0), (2, 1, 1), (3, 2, 2), (5, 1, 1)):
        mix.add(trumpet(hz(hi[i]), d * beat * .85), t0 + pos * beat + human(.003), .3, -.25, .3)
    hit(mix, "war", t0, .5, 0, .25)
    hit(mix, "war", t0 + 3 * beat, .42, 0, .25)
    for i in range(6):
        hit(mix, "jingle", t0 + i * beat, .15, .45)
    if bar % 4 == 3:
        roll(mix, "tabor", t0 + 3 * beat, 6, beat / 2, .15, .42)


def tension_clash(mix, chord, t0, beat, bar, sec, energy, th):
    bass, tones = CHORDS[chord]
    for i in range(16):
        for j, name in enumerate(tones[1:3]):
            mix.add(bowed(hz(name) * 2, beat / 4 * .95, "vielle", att=.008), t0 + i * beat / 4 + human(.002), .09 if i % 4 else .13, -.3 + .2 * j, .3)
    for pos in (0, 1.5, 3):
        mix.add(trumpet(hz(tones[-1]), .3), t0 + pos * beat + human(.003), .3, .25, .3)
    for i in range(8):
        hit(mix, "war", t0 + i * beat / 2, .5 if i in (0, 3, 6) else .24, 0, .25)


def tension_siege(mix, chord, t0, beat, bar, sec, energy, th):
    bass, tones = CHORDS[chord]
    root = hz(bass) * (2 if hz(bass) < 100 else 1)
    for f in (root, root * 1.5, root * 2):
        mix.add(choir(f, 4 * beat, "a"), t0, .16, 0, .5)
    if bar % 2 == 0:
        mix.add(bell(hz(th["bell"]), 5.0), t0, .2, .3, .5)
    for pos in (0, 2.5):
        mix.add(trumpet(hz(tones[-1]), .35), t0 + pos * beat + human(.003), .28, -.25, .3)
    for i in range(8):
        hit(mix, "war", t0 + i * beat / 2, .5 if i in (0, 4) else .24, 0, .25)


BASES = {"march": base_march, "harp": base_harp, "dirge": base_dirge, "riff": base_riff, "jig": base_jig, "gallop": base_gallop, "chop": base_chop, "epic": base_epic}
DRUMS = {"march": drums_march, "magic": drums_magic, "heartbeat": drums_heartbeat, "tribal": drums_tribal, "jig": drums_jig, "gallop": drums_gallop, "duel": drums_duel, "epic": drums_epic}
TENSIONS = {"fanfare": tension_fanfare, "spark": tension_spark, "dread": tension_dread, "horde": tension_horde, "reel": tension_reel, "charge": tension_charge, "clash": tension_clash, "siege": tension_siege}


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
    "E": ("E2", ["B2", "E3", "G#3", "B3", "E4", "G#4"]),
}


def strum(mix: Mix, chord: str, at: float, gain: float = 0.5, spread: float = 0.022, ring: float = 2.4, pan: float = -0.2, up: bool = False) -> None:
    bass, tones = CHORDS[chord]
    notes = [bass] + tones
    if up:
        notes = notes[::-1]
    for i, name in enumerate(notes):
        mix.add(pluck(hz(name), ring, 1.1), at + i * spread + human(0.002), gain * (1.0 if i == 0 else 0.7) * float(rng.uniform(0.9, 1.05)), pan + i * 0.05, 0.3)



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



# ---- battle themes (2026-11-24) ----------------------------------------------------------------
# Each theme is a little medieval consort piece in a church mode, written as four loops of the same
# length that play in step (music_player.gd): "lute" = the accompaniment (lute, harp, organ, drones;
# always on), "drums", "tune" = the melody, and "tension" = a danger layer raised when the battle
# turns (shawm calls, war drums, tremolo strings, chant). A form entry is
# (progression, tune, voices, ornamented, energy 0..2); voices may be ("split", a, b, bars) for call
# and answer. 4/4 themes count in quarter notes; 6/8 themes count in eighths (bpm = eighths a minute).
THEMES = {
    "normal": {  # 經典・王國行軍：D Dorian，112 拍。魯特琴進行曲、手搖琴持續音、木笛與維奧爾琴，危急時肖姆管號角
        "bpm": 112, "meter": 4, "scale": "D E F G A B C", "base": "march", "drums": "march", "tension": "fanfare",
        "drone": ("D3", "A3"), "drone_gain": .085,
        "prog": {"A": ["Dm", "Dm", "C", "Dm", "Dm", "F", "C", "Dm"], "B": ["F", "C", "Dm", "Am", "F", "G", "Am", "Dm"],
                 "C": ["Dm", "C", "Dm", "G", "F", "C", "A", "Dm"]},
        "tunes": {
            "a": ["D5:1 E5:.5 F5:.5 G5:1 F5:.5 E5:.5", "D5:1.5 E5:.5 F5:1 A5:1", "G5:1 F5:.5 E5:.5 C5:1 E5:1", "D5:3 R:1",
                  "A5:1 A5:.5 G5:.5 F5:1 A5:1", "C6:1.5 A5:.5 F5:1 G5:.5 A5:.5", "G5:1 E5:.5 D5:.5 C5:1 E5:1", "D5:3 R:1"],
            "b": ["A5:1.5 G5:.5 F5:1 C5:1", "E5:1 G5:1 E5:.5 D5:.5 C5:1", "D5:1 F5:1 A5:1 D6:1", "C6:1 B5:.5 A5:.5 E5:2",
                  "F5:1 A5:1 C6:1 A5:1", "B5:1.5 A5:.5 G5:1 D5:1", "E5:1 C5:.5 D5:.5 E5:1 A4:1", "D5:4"],
            "c": ["D5:.75 D5:.25 A5:1 A5:.75 G5:.25 F5:1", "E5:.75 E5:.25 G5:1 C5:2", "D5:.75 D5:.25 F5:1 A5:1 D6:1", "B5:2 G5:2",
                  "A5:.75 G5:.25 F5:1 C6:1 A5:1", "G5:.75 F5:.25 E5:1 C5:2", "E5:1 D5:.5 C#5:.5 E5:1 A4:1", "D5:3 R:1"]},
        "voices": {"rec_lute": [("recorder", 0, .5, .15), ("lute", -1, .28, -.3)], "vielle": [("vielle", -1, .46, -.12)],
                   "duo": [("recorder", 0, .42, .18), ("vielle", -1, .34, -.15)], "rec": [("recorder", 0, .5, .15)],
                   "band": [("shawm", -1, .36, .25), ("recorder", 0, .28, -.05), ("vielle", -1, .26, -.2)]},
        "form": [("A", "a", "rec_lute", 0, 0), ("A", "a", "vielle", 1, 1), ("B", "b", "duo", 0, 1), ("B", "b", "rec", 1, 1),
                 ("C", "c", "band", 0, 2), ("A", "a", "duo", 1, 1), ("C", "c", "band", 1, 2), ("B", "b", "band", 1, 2)]},
    "magic": {  # 魔法・星象塔：F Lydian，100 拍。豎琴十六分音符分解和弦、攜帶式管風琴、手鈴與指鈸
        "bpm": 100, "meter": 4, "scale": "F G A B C D E", "base": "harp", "drums": "magic", "tension": "spark",
        "prog": {"P1": ["F", "G", "F", "G", "Am", "G", "F", "F"], "P2": ["Dm", "Am", "G", "G", "F", "C", "G", "F"],
                 "P3": ["Dm", "Dm", "C", "C", "Am", "Am", "G", "G"]},
        "tunes": {
            "a": ["C5:1 F5:1 A5:1.5 G5:.5", "B5:2 A5:1 G5:1", "A5:1 C6:1 F5:1.5 G5:.5", "G5:2 D5:2",
                  "E5:1 A5:1 C6:1 B5:1", "D6:1.5 C6:.5 B5:1 G5:1", "A5:1 G5:1 F5:1 E5:1", "F5:4"],
            "b": ["D6:1.5 C6:.5 A5:2", "C6:1 B5:1 A5:1 E5:1", "G5:1 B5:1 D6:2", "B5:1 A5:1 G5:2",
                  "A5:1 C6:1 F6:1.5 E6:.5", "E6:1 D6:1 C6:1 G5:1", "B5:1.5 A5:.5 G5:1 B5:1", "A5:2 F5:2"],
            "c": ["D5:2 F5:1 A5:1", "G5:1 F5:1 E5:1 D5:1", "E5:2 G5:1 C6:1", "B5:1 A5:1 G5:2",
                  "A5:1.5 B5:.5 C6:1 E6:1", "D6:1 C6:1 B5:1 A5:1", "B5:2 D6:1 B5:1", "G5:3 R:1"]},
        "voices": {"rec": [("recorder", 0, .44, .15), ("harp", -1, .2, -.3)], "organ": [("organ", 0, .36, .1)],
                   "organ_low": [("organ", -1, .38, 0)], "bells": [("recorder", 0, .42, .15), ("bells", 0, .18, .35, 1)],
                   "all": [("organ", 0, .28, .1), ("recorder", 0, .3, -.1), ("bells", 1, .12, .35, 1)]},
        "form": [("P1", "a", "rec", 0, 0), ("P1", "a", "organ", 1, 1), ("P2", "b", "bells", 0, 1), ("P3", "c", "organ_low", 0, 1),
                 ("P1", "a", "bells", 1, 2), ("P2", "b", "rec", 1, 2), ("P3", "c", "organ", 1, 1), ("P2", "b", "all", 0, 2)]},
    "dark": {  # 黑暗・深淵喪鐘：D Phrygian，76 拍。大教堂殘響、低音弓弦持續音、喪鐘、修士吟唱與心跳戰鼓
        "bpm": 76, "meter": 4, "scale": "D Eb F G A Bb C", "base": "dirge", "drums": "heartbeat", "tension": "dread",
        "hall": "cathedral", "drone": ("D2", "A2"), "drone_kind": "bass", "drone_gain": .13, "drone_from": 0, "bell": "D3",
        "prog": {"P1": ["Dm", "Dm", "Eb", "Dm", "Dm", "Cm", "Eb", "Dm"], "P2": ["Gm", "Gm", "Dm", "Dm", "Eb", "Eb", "Dm", "Dm"],
                 "P3": ["Bb", "Cm", "Dm", "Dm", "Bb", "Cm", "Eb", "Dm"]},
        "tunes": {
            "a": ["D4:2 Eb4:1 F4:1", "G4:1.5 F4:.5 Eb4:1 D4:1", "Eb4:1 G4:1 Bb4:2", "A4:3 R:1",
                  "A4:1 Bb4:1 A4:1 F4:1", "G4:1.5 F4:.5 Eb4:1 C4:1", "Eb4:2 F4:1 Eb4:1", "D4:4"],
            "b": ["G4:2 Bb4:1 A4:1", "G4:1 F4:1 D4:2", "A4:1 C5:1 D5:2", "C5:1 Bb4:1 A4:2",
                  "Bb4:1.5 C5:.5 Bb4:1 G4:1", "Eb5:2 D5:1 Bb4:1", "A4:1 G4:1 F4:1 Eb4:1", "D4:3 R:1"],
            "c": ["F4:1 Bb4:1 D5:2", "Eb5:1.5 D5:.5 C5:2", "D5:1 A4:1 F4:1 A4:1", "D5:3 R:1",
                  "D5:1 C5:1 Bb4:1 F4:1", "G4:1 C5:1 Eb5:1 D5:1", "C5:1 Bb4:1 G4:1 Eb4:1", "D4:4"]},
        "voices": {"low": [("vielle", 0, .48, -.1)], "chant": [("choir:u", -1, .44, 0, 1), ("vielle", 0, .3, -.15)],
                   "full": [("crumhorn", 0, .3, .25), ("vielle", 0, .34, -.15), ("choir:o", -1, .3, 0, 1)]},
        "form": [("P1", "a", "low", 0, 0), ("P1", "a", "chant", 0, 1), ("P2", "b", "low", 1, 1), ("P3", "c", "chant", 0, 2),
                 ("P2", "b", "full", 1, 2), ("P1", "a", "chant", 1, 1)]},
    "beast": {  # 魔物・荒野狂踏：G Phrygian，132 拍。3＋3＋2 戰鼓與小定音鼓、手搖琴蜂鳴、肖姆管與彎角管
        "tune_gain": 2.4, "bpm": 132, "meter": 4, "scale": "G Ab Bb C D Eb F", "base": "riff", "drums": "tribal", "tension": "horde",
        "drone": ("G2", "D3"), "drone_gain": .09,
        "prog": {"P1": ["Gm", "Gm", "Ab", "Gm", "Gm", "Fm", "Ab", "Gm"], "P2": ["Cm", "Cm", "Gm", "Gm", "Eb", "Fm", "Ab", "Gm"],
                 "P3": ["Eb", "Eb", "Fm", "Fm", "Ab", "Fm", "Ab", "Gm"]},
        "tunes": {
            "a": ["G4:1.5 Bb4:1.5 D5:1", "C5:1.5 Bb4:1.5 G4:1", "Ab4:1.5 C5:1.5 Eb5:1", "D5:2 G4:2",
                  "G5:1.5 F5:1.5 D5:1", "F5:1.5 Eb5:1.5 C5:1", "Eb5:1 C5:1 Ab4:1 Bb4:1", "G4:3 R:1"],
            "b": ["C5:1 Eb5:1 G5:2", "G5:1.5 F5:1.5 Eb5:1", "D5:1 G5:1 Bb5:2", "Ab5:1.5 G5:1.5 D5:1",
                  "Eb5:1.5 G5:1.5 Bb5:1", "Ab5:1.5 G5:1.5 F5:1", "Eb5:1 F5:.5 Eb5:.5 C5:1 Ab4:1", "G4:2 D5:2"],
            "c": ["Bb5:3 G5:1", "Ab5:1 G5:1 Eb5:2", "C6:3 Ab5:1", "G5:1 F5:1 C5:2",
                  "Eb5:1.5 Ab5:1.5 C6:1", "C6:1.5 Ab5:1.5 F5:1", "Eb5:1 Ab5:1 G5:1 F5:1", "G5:4"]},
        "voices": {"shawm": [("shawm", 0, .46, .2)], "horde": [("shawm", 0, .4, .2), ("gurdy", 0, .3, -.2)],
                   "crum": [("crumhorn", 0, .42, .15), ("vielle", -1, .28, -.2)]},
        "form": [("P1", "a", "shawm", 0, 0), ("P1", "a", "horde", 1, 1), ("P2", "b", "shawm", 0, 1), ("P1", "a", "crum", 1, 1),
                 ("P3", "c", "horde", 0, 2), ("P2", "b", "horde", 1, 2), ("P3", "c", "crum", 1, 2), ("P1", "a", "horde", 0, 2)]},
    "conveyor": {  # 補給傳送帶・工坊吉格：G Mixolydian，6/8（附點四分 104）。輕快吉格舞曲，木笛與維奧爾琴輪唱
        "bpm": 312, "meter": 6, "orn_unit": .5, "scale": "G A B C D E F", "base": "jig", "drums": "jig", "tension": "reel",
        "drone": ("G3", "D4"), "drone_gain": .06,
        "prog": {"P1": ["G", "G", "F", "G", "C", "G", "F", "G"], "P2": ["C", "C", "G", "G", "Am", "F", "G", "G"],
                 "P3": ["Am", "Am", "G", "G", "F", "C", "Dm", "G"]},
        "tunes": {
            "a": ["G5:2 B5:1 D6:2 B5:1", "A5:1 B5:1 G5:1 D5:2 G5:1", "F5:2 A5:1 C6:2 A5:1", "B5:1 A5:1 G5:1 D5:3",
                  "E5:1 G5:1 C6:1 B5:1 A5:1 G5:1", "D6:2 B5:1 G5:2 B5:1", "A5:1 G5:1 F5:1 E5:1 F5:1 A5:1", "G5:4 R:2"],
            "b": ["C6:2 E6:1 D6:1 C6:1 B5:1", "A5:1 G5:1 E5:1 G5:3", "B5:2 D6:1 G6:2 D6:1", "F6:1 E6:1 D6:1 B5:3",
                  "C6:1 B5:1 A5:1 E5:2 A5:1", "F5:2 A5:1 C6:2 A5:1", "B5:1 A5:1 G5:1 F5:1 E5:1 D5:1", "G5:4 R:2"],
            "c": ["E5:1 A5:1 B5:1 C6:2 B5:1", "A5:1 G5:1 E5:1 A5:3", "D5:1 G5:1 A5:1 B5:2 A5:1", "G5:1 F5:1 D5:1 G5:3",
                  "F5:1 A5:1 C6:1 F6:2 E6:1", "E6:1 D6:1 C6:1 G5:3", "F5:1 E5:1 D5:1 A5:2 F5:1", "G5:4 R:2"]},
        "voices": {"rec": [("recorder", 0, .48, .15)], "fiddle": [("vielle", -1, .44, -.12)],
                   "duo": [("recorder", 0, .4, .18), ("vielle", -1, .32, -.15)],
                   "full": [("recorder", 0, .34, .18), ("vielle", -1, .28, -.15), ("crumhorn", -1, .22, .3)]},
        "form": [("P1", "a", "rec", 0, 0), ("P1", "a", "fiddle", 1, 1), ("P2", "b", "rec", 0, 1), ("P2", "b", "duo", 1, 1),
                 ("P1", "a", "duo", 1, 2), ("P3", "c", "fiddle", 0, 1), ("P3", "c", "duo", 1, 2), ("P2", "b", "full", 0, 2),
                 ("P1", "a", "rec", 1, 1), ("P1", "a", "full", 0, 2)]},
    "charge": {  # 五路衝鋒・薩爾塔雷洛：A Aeolian，6/8（附點四分 124）。長短馳騁節奏、自然小號與肖姆管
        "tune_gain": 2.2, "bpm": 372, "meter": 6, "orn_unit": .5, "scale": "A B C D E F G", "base": "gallop", "drums": "gallop", "tension": "charge",
        "drone": ("A2", "E3"), "drone_gain": .085,
        "prog": {"A": ["Am", "Am", "G", "Am", "F", "G", "E", "Am"], "B": ["F", "G", "Am", "Am", "Dm", "Em", "F", "E"],
                 "C": ["C", "G", "Am", "Em", "F", "C", "Dm", "E"]},
        "tunes": {
            "a": ["A4:2 C5:1 E5:2 A5:1", "G5:2 E5:1 C5:2 E5:1", "D5:2 G5:1 B5:2 G5:1", "A5:3 E5:3",
                  "F5:2 A5:1 C6:2 A5:1", "B5:2 A5:1 G5:2 D5:1", "E5:2 G#5:1 B5:2 G#5:1", "A5:4 R:2"],
            "b": ["C6:2 A5:1 F5:2 A5:1", "D6:2 B5:1 G5:2 B5:1", "E6:2 C6:1 A5:2 C6:1", "B5:1 C6:1 B5:1 A5:3",
                  "F5:2 A5:1 D6:2 A5:1", "G5:2 B5:1 E6:2 B5:1", "A5:2 C6:1 F5:2 A5:1", "E5:3 G#5:2 B5:1"],
            "c": ["C5:1 E5:1 G5:1 C6:3", "B5:1 A5:1 G5:1 D5:3", "E5:1 A5:1 C6:1 E6:3", "D6:1 C6:1 B5:1 G5:3",
                  "A5:2 C6:1 F6:2 C6:1", "E6:2 C6:1 G5:2 E5:1", "F5:2 A5:1 D6:2 F5:1", "E5:3 B4:3"]},
        "voices": {"shawm": [("shawm", -1, .46, .2)], "rec": [("recorder", 0, .42, .15), ("vielle", -1, .3, -.15)],
                   "trump": [("trumpet", -1, .42, -.15), ("shawm", -1, .28, .25)],
                   "full": [("trumpet", -1, .34, -.15), ("shawm", -1, .26, .25), ("recorder", 0, .26, .05)]},
        "form": [("A", "a", "shawm", 0, 0), ("A", "a", "rec", 1, 1), ("B", "b", "shawm", 0, 1), ("A", "a", "trump", 1, 2),
                 ("C", "c", "trump", 0, 2), ("C", "c", "rec", 1, 1), ("B", "b", "trump", 1, 2), ("A", "a", "shawm", 1, 1),
                 ("B", "b", "rec", 0, 1), ("C", "c", "full", 1, 2), ("A", "a", "full", 0, 2), ("A", "a", "trump", 1, 2)]},
    "duel": {  # 鐵血交鋒・領主死鬥：C Aeolian，120 拍。肖姆管與維奧爾琴一問一答、小定音鼓 3＋3＋2、弓弦斷奏
        "loud": 1.12, "tune_gain": 1.9, "bpm": 120, "meter": 4, "scale": "C D Eb F G Ab Bb", "base": "chop", "drums": "duel", "tension": "clash",
        "prog": {"U1": ["Cm", "Cm", "Bb", "Bb", "Ab", "Ab", "G", "G"], "U2": ["Cm", "Fm", "Cm", "Fm", "Eb", "Bb", "Ab", "G"],
                 "U3": ["Ab", "Bb", "Cm", "Cm", "Ab", "Bb", "G", "G"]},
        "tunes": {
            "a": ["C5:1 Eb5:.5 G5:.5 C6:1 G5:1", "Bb5:.5 Ab5:.5 G5:1 Eb5:2", "D5:1 F5:.5 Bb5:.5 D6:1 Bb5:1", "C6:.5 Bb5:.5 Ab5:1 F5:2",
                  "C6:1 Eb6:.5 C6:.5 Ab5:1 Eb5:1", "F5:.5 G5:.5 Ab5:1 C6:2", "B5:1 D6:.5 B5:.5 G5:1 D5:1", "G5:3 R:1"],
            "b": ["G5:1.5 Eb5:.5 C5:1 G4:1", "Ab4:1 C5:1 F5:2", "Eb5:1.5 G5:.5 C6:1 G5:1", "Ab5:1 G5:1 F5:2",
                  "G5:1 Bb5:1 Eb6:1 D6:1", "F6:1.5 Eb6:.5 D6:1 Bb5:1", "C6:1 Ab5:1 Eb5:1 C5:1", "B4:1 D5:1 G5:2"],
            "c": ["Eb5:.5 F5:.5 Ab5:1 C6:1 Ab5:1", "F5:.5 G5:.5 Bb5:1 D6:1 Bb5:1", "G5:.5 Bb5:.5 C6:1 Eb6:1 C6:1", "D6:1 C6:1 G5:2",
                  "Ab5:1 C6:1 Eb6:1.5 D6:.5", "D6:1 Bb5:1 F5:1 D5:1", "B4:.5 D5:.5 G5:.5 B5:.5 D6:1 B5:1", "G5:2 D5:2"]},
        "voices": {"shawm": [("shawm", -1, .46, .22)], "vielle": [("vielle", -1, .48, -.18)],
                   "both": [("shawm", -1, .36, .22), ("vielle", -1, .34, -.18)],
                   "all": [("shawm", -1, .32, .22), ("vielle", -1, .3, -.18), ("trumpet", -1, .22, 0)]},
        "form": [("U1", "a", ("split", "shawm", "vielle", 2), 0, 0), ("U2", "b", "vielle", 0, 1), ("U1", "a", ("split", "shawm", "vielle", 2), 1, 1),
                 ("U3", "c", "both", 0, 2), ("U2", "b", "shawm", 1, 1), ("U3", "c", "both", 1, 2),
                 ("U1", "a", ("split", "vielle", "shawm", 2), 1, 1), ("U1", "a", "all", 0, 2)]},
    "crimson": {  # 赤旗總攻・破陣之歌：E Aeolian／Phrygian 終止，128 拍。自然小號齊奏、戰鼓、修士合唱與大鐘
        "tune_gain": 2.1, "bpm": 128, "meter": 4, "scale": "E F# G A B C D", "base": "epic", "drums": "epic", "tension": "siege",
        "drone": ("E2", "B2"), "drone_gain": .09, "drone_from": 0, "bell": "E3",
        "prog": {"R1": ["Em", "Em", "D", "Em", "C", "D", "F", "Em"], "R2": ["C", "D", "Em", "Em", "Am", "C", "B", "B"],
                 "R3": ["F", "G", "Am", "Em", "F", "D", "B", "B"]},
        "tunes": {
            "a": ["E5:1 B4:.5 E5:.5 G5:1 B5:1", "A5:.5 G5:.5 F#5:1 E5:2", "D5:1 A4:.5 D5:.5 F#5:1 A5:1", "G5:1 F#5:1 E5:2",
                  "E5:1 G5:1 C6:1 B5:1", "A5:1.5 G5:.5 F#5:1 D5:1", "F5:1 A5:1 C6:1 A5:1", "E5:3 R:1"],
            "b": ["G5:1 C6:1 E6:2", "F#6:1 E6:1 D6:2", "B5:1.5 A5:.5 G5:1 E5:1", "B5:3 R:1",
                  "C6:1 B5:1 A5:1 E5:1", "G5:1 A5:1 C6:2", "B5:1 A5:1 F#5:1 D#5:1", "B5:4"],
            "c": ["C6:2 A5:1 F5:1", "D6:2 B5:1 G5:1", "E6:1.5 D6:.5 C6:1 A5:1", "B5:1 G5:1 E5:2",
                  "A5:1 C6:1 F6:2", "F#6:1 E6:1 D6:1 A5:1", "D#6:1 B5:1 F#5:1 D#5:1", "B5:2 F#5:2"]},
        "voices": {"trump": [("trumpet", -1, .42, -.15), ("shawm", -1, .28, .25)],
                   "rec": [("recorder", 0, .4, .15), ("vielle", -1, .32, -.15)],
                   "choir": [("trumpet", -1, .36, -.15), ("choir:a", -1, .3, 0, 1), ("vielle", -1, .24, .2)]},
        "form": [("R1", "a", "trump", 0, 1), ("R1", "a", "rec", 1, 1), ("R2", "b", "trump", 0, 2), ("R3", "c", "choir", 0, 2),
                 ("R1", "a", "choir", 1, 2), ("R2", "b", "rec", 1, 1), ("R3", "c", "trump", 0, 2), ("R1", "a", "choir", 0, 2)]},
}

NIGHT = {  # 入夜：城牆崩落的總攻。D Aeolian，136 拍。警鐘、戰鼓、手搖琴蜂鳴、小號與肖姆管
    "bpm": 136, "meter": 4, "scale": "D E F G A Bb C", "base": "epic", "drums": "epic", "tension": "siege",
    "drone": ("D2", "A2"), "drone_gain": .09, "drone_from": 0, "bell": "D3",
    "prog": {"n1": ["Dm", "Dm", "Bb", "C", "Dm", "Dm", "Gm", "A"], "n2": ["Dm", "Dm", "Bb", "C", "Gm", "A", "Dm", "Dm"],
             "n3": ["F", "C", "Gm", "A", "Dm", "Bb", "Gm", "A"]},
    "tunes": {
        "a": ["D5:.5 D5:.5 F5:.5 E5:.5 D5:1 A4:1", "D5:.5 D5:.5 F5:.5 G5:.5 A5:2", "Bb5:1 A5:.5 G5:.5 F5:1 D5:1", "E5:1 G5:1 E5:1 C5:1",
              "D5:.5 D5:.5 F5:.5 E5:.5 D5:1 A4:1", "D5:.5 E5:.5 F5:.5 G5:.5 A5:2", "Bb5:1 G5:1 D5:1 G5:1", "A5:1 E5:1 C#5:1 E5:1"],
        "b": ["A5:.5 A5:.5 D6:1 A5:1 F5:1", "G5:.5 F5:.5 E5:.5 F5:.5 D5:2", "F5:1 D5:.5 F5:.5 Bb5:1 A5:1", "G5:1 E5:1 C5:1 E5:1",
              "D5:1 G5:.5 A5:.5 Bb5:1 G5:1", "A5:1.5 G5:.5 E5:1 C#5:1", "D5:1 A4:.5 D5:.5 F5:1 E5:1", "D5:3 R:1"],
        "c": ["A5:1 F5:1 C5:1 F5:1", "G5:1 E5:1 C5:1 E5:1", "G5:.5 A5:.5 Bb5:1 A5:1 G5:1", "A5:2 E5:1 C#5:1",
              "D5:.5 D5:.5 F5:.5 E5:.5 D5:1 A4:1", "Bb4:1 D5:1 F5:1 Bb5:1", "A5:.5 G5:.5 F5:.5 G5:.5 Bb5:1 G5:1", "A5:1 C#5:1 E5:1 A5:1"]},
    "voices": {"horns": [("trumpet", -1, .42, -.15), ("shawm", -1, .3, .25)],
               "all": [("trumpet", -1, .36, -.15), ("shawm", -1, .26, .25), ("vielle", -1, .26, 0)]},
    "form": [("n1", "a", "horns", 0, 2), ("n2", "b", "horns", 0, 2), ("n3", "c", "all", 1, 2), ("n2", "b", "all", 1, 2), ("n1", "a", "all", 1, 2)],
}


def render_parts(th: dict) -> list:
    """The four loops of one theme: [accompaniment, drums, tune, tension]."""
    meter = th["meter"]
    beat = 60 / th["bpm"]
    for key, bars in th["tunes"].items():
        for i, bar in enumerate(bars):
            total = sum(b for _, b in line(bar))
            assert abs(total - meter) < 1e-6, f"tune {key} bar {i} has {total} beats, not {meter}: {bar}"
    seconds = sum(len(th["prog"][f[0]]) for f in th["form"]) * meter * beat
    ir = CATHEDRAL if th.get("hall") == "cathedral" else ROOM
    mixes = [Mix(seconds, True, ir) for _ in range(4)]
    base, drums, tune, tension = mixes
    bar = 0
    for sec, (prog_key, tune_key, voice_key, orn, energy) in enumerate(th["form"]):
        prog = th["prog"][prog_key]
        bars = th["tunes"][tune_key]
        if orn:
            bars = [ornament(b, th, 100 * sec + i) for i, b in enumerate(bars)]
        for i, b in enumerate(bars):
            key = voice_key
            if isinstance(voice_key, tuple):  # call and answer
                key = voice_key[1] if (i // voice_key[3]) % 2 == 0 else voice_key[2]
            for v in th["voices"][key]:
                play_line(tune, v[0], [b], beat, (bar + i) * meter, v[2], v[3], v[1], v[4] if len(v) > 4 else 0.0)
        start = bar * meter * beat
        if th.get("drone") and energy >= th.get("drone_from", 1):
            for j, note in enumerate(th["drone"]):
                drone = bowed(hz(note), len(prog) * meter * beat + 0.3, th.get("drone_kind", "drone"), att=0.5)
                base.add(drone, start, th.get("drone_gain", .09) * (1 if j == 0 else .8), .25 - .5 * j, .3)
        for chord in prog:
            t0 = bar * meter * beat
            BASES[th["base"]](base, chord, t0, beat, bar, sec, energy, th)
            DRUMS[th["drums"]](drums, t0, beat, bar, sec, energy, th)
            TENSIONS[th["tension"]](tension, chord, t0, beat, bar, sec, energy, th)
            bar += 1
    parts = [m.render(air=th.get("air", .3)) for m in mixes]
    parts[2] *= th.get("tune_gain", 1.7)  # the melody sits on top of the consort, not inside it
    return parts


def theme(name: str) -> None:
    parts = level(render_parts(THEMES[name]), 0.86)
    parts = [p * THEMES[name].get("loud", 1.0) for p in parts]  # evens out themes whose peaks are spikier than their body
    for layer, part in zip(("lute", "drums", "tune", "tension"), parts):
        save(f"battle_{name}_{layer}", part, quality=3)


def battle(*names: str) -> None:
    for name in names or THEMES:
        theme(name)


def night() -> None:
    """入夜：四層一起演奏（緊張層略收），單一循環。"""
    base, drums, tune, tension = render_parts(NIGHT)
    save("night", level([base + drums + tune + 0.75 * tension], 0.86)[0], quality=4)


def menu() -> None:
    """標題與選單：三拍子魯特琴分解和弦、手搖琴輕輕的持續音；後半豎琴與手鼓加入，木笛唱主題。D Dorian，88 拍。"""
    beat = 60 / 88
    prog = ["Dm", "Dm", "C", "C", "Dm", "G", "Am", "Dm", "F", "C", "Dm", "Am", "F", "G", "Am", "Dm"]
    arps = {"Dm": ["A3", "D4", "F4", "D4", "A3"], "C": ["G3", "C4", "E4", "C4", "G3"], "G": ["B3", "D4", "G4", "D4", "B3"], "Am": ["A3", "C4", "E4", "C4", "A3"], "F": ["A3", "C4", "F4", "C4", "A3"]}
    tune = ["D5:2 E5:1", "F5:1 E5:1 D5:1", "C5:2 E5:1", "G4:3", "A4:1 D5:1 F5:1", "G5:2 F5:1", "E5:1.5 D5:.5 C5:1", "D5:3",
            "F5:2 A5:1", "G5:1 E5:1 C5:1", "D5:1 F5:1 A5:1", "E5:3", "F5:1 E5:1 D5:1", "B4:1 D5:1 G5:1", "E5:1.5 C5:.5 E5:1", "D5:3"]
    mix = Mix(32 * 3 * beat, True)
    for half in (0, 16):
        for j, note in enumerate(("D3", "A3")):
            mix.add(bowed(hz(note), 16 * 3 * beat + 0.4, "drone", att=1.2), half * 3 * beat, .05 if j == 0 else .04, .3 - .5 * j, .35)
    for bar in range(32):
        chord = prog[bar % 16]
        t0 = bar * 3 * beat
        second = bar >= 16
        mix.add(pluck(hz(CHORDS[chord][0]), 3.0, 0.85), t0 + human(), 0.56, -0.14, 0.28)
        for i, name in enumerate(arps[chord]):
            mix.add(pluck(hz(name), 2.1, 0.98), t0 + (i + 1) * beat / 2 + human(), 0.33 * (1.12 if i == 2 else 1.0) * float(rng.uniform(0.88, 1.06)), -0.25 + i * 0.1, 0.28)
        if second:
            hit(mix, "dum", t0, .26, 0, .3)
            hit(mix, "jingle", t0 + 2 * beat, .1, .4, .3)
            if bar % 2 == 1:
                mix.add(harp(hz(arps[chord][2]) * 2, 2.4), t0 + 2.5 * beat + human(), 0.2, 0.45, 0.4)
    play_line(mix, "recorder", tune, beat, 16 * 3, 0.40, 0.20)
    play_line(mix, "vielle", tune, beat, 16 * 3, 0.16, -0.25, -1)
    save("menu", level([mix.render()], 0.85)[0], quality=4)


def victory() -> None:
    """勝利：D 大調自然小號號角，塔布鼓滾奏、手鈴與管風琴收在大和弦上。"""
    beat = 60 / 128
    mix = Mix(9.0, False)
    fan = ["A4:.5 D5:.5 F#5:.5 A5:1.5", "B5:.5 A5:.5 G5:.5 A5:.5", "D6:5"]
    play_line(mix, "trumpet", fan, beat, 0, .5, -.15, -1)
    play_line(mix, "shawm", fan, beat, 0, .24, .25, -1)
    play_line(mix, "recorder", fan, beat, 0, .2, .1, 0)
    for note, g, pan in (("A4", .3, .3), ("F#4", .26, -.35)):
        mix.add(trumpet(hz(note), 5 * beat * .86), 5 * beat, g, pan, .3)
    strum(mix, "D", 0.0, 0.48, 0.018, 2.8)
    strum(mix, "G", 3 * beat, 0.44, 0.016, 2.2)
    strum(mix, "D", 5 * beat, 0.62, 0.025, 4.5)
    strum(mix, "D", 5 * beat + 0.45, 0.34, 0.018, 4.0, 0.3, up=True)
    for at, g in ((0.0, .62), (3 * beat, .55), (5 * beat, .75)):
        hit(mix, "war", at, g, 0, .3)
    for at in (1.5 * beat, 2 * beat):
        hit(mix, "tabor", at, .4, .1)
    roll(mix, "tabor", 3.5 * beat, 6, beat / 4, .15, .45)
    for i, note in enumerate(("D5", "F#5", "A5", "D6", "F#6")):
        mix.add(handbell(hz(note), 3.0), 5 * beat + i * beat * .3, .16, -.35 + i * .17, .4)
    for note in ("D3", "A3", "D4", "F#4"):
        mix.add(organ(hz(note), 3.4), 5 * beat, .09, 0, .4)
    for j in range(14):
        hit(mix, "jingle", 5 * beat + j * 0.07, .06 + .16 * np.sin(np.pi * j / 14), .4)
    audio = mix.render()
    audio[-SR:] *= np.linspace(1, 0, SR)[:, None]
    save("victory", level([audio], 0.88)[0], quality=4)


def defeat() -> None:
    """敗北：D 小調輓歌，大教堂裡的喪鐘、魯特琴、木笛與維奧爾琴，修士低聲合唱收尾。"""
    beat = 60 / 66
    mix = Mix(10.5, False, CATHEDRAL)
    mix.add(bell(146.83, 6.0), 0.0, 0.50, -0.2, 0.5)
    for name, at_b, dur_b, g in (("D2", 0.0, 1.9, .2), ("Bb2", 2.0, .95, .17), ("A2", 3.0, .95, .18), ("D2", 4.0, 4.8, .22)):
        mix.add(bowed(hz(name), dur_b * beat, "bass"), at_b * beat, g, -.1, .35)
    for i, name in enumerate(["D2", "A2", "D3", "F3"]):
        mix.add(pluck(hz(name), 3.5, 0.8), i * beat / 2, 0.50, -0.2, 0.35)
    lament = ["A4:1.5 G4:.5 F4:1 E4:1", "D4:4"]
    play_line(mix, "recorder", lament, beat, 0, .44, .16)
    play_line(mix, "vielle", lament, beat, 0, .2, -.2, -1)
    for i, name in enumerate(["Bb2", "F3", "Bb3"]):
        mix.add(pluck(hz(name), 3.0, 0.8), 2 * beat + i * 0.03, 0.38, -0.2, 0.35)
    for i, name in enumerate(["A2", "E3", "A3", "C#4"]):
        mix.add(pluck(hz(name), 3.0, 0.8), 3 * beat + i * 0.03, 0.38, -0.2, 0.35)
    for i, name in enumerate(["D2", "A2", "D3"]):
        mix.add(pluck(hz(name), 5.0, 0.75), 4 * beat + i * 0.05, 0.55, -0.2, 0.4)
    for note in ("D3", "A3"):
        mix.add(choir(hz(note), 4.2 * beat, "u"), 4 * beat, .14, 0, .5)
    audio = mix.render()
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
    for name in (sys.argv[1:] or [p for p in PIECES if p != "previews"]):
        piece, _, arg = name.partition(":")
        PIECES[piece](*([arg] if arg else []))
