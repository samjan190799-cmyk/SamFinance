"""Музыка и звуки ролика, синтезированные кодом: короткая своя мелодия, чужих записей и прав третьих лиц нет."""
import wave

import numpy as np

SR = 48000
BPM = 100
BEAT = 60.0 / BPM

# По аккорду на такт: (бас, ноты подложки, ноты арпеджио). Ля минор: Am - F - C - G.
CHORDS = [
    (45, [57, 60, 64, 71], [69, 72, 76, 81]),
    (41, [53, 57, 60, 67], [65, 69, 72, 77]),
    (48, [55, 60, 64, 71], [67, 72, 76, 79]),
    (43, [55, 59, 62, 69], [67, 71, 74, 79]),
]
ARP_PATTERN = [0, 1, 2, 3, 2, 1, 2, 3]


def _hz(note):
    return 440.0 * 2 ** ((note - 69) / 12)


def _t(duration):
    return np.arange(int(duration * SR)) / SR


def _stereo(mono, pan):
    """pan от -1 (слева) до 1 (справа)."""
    left = np.cos((pan + 1) * np.pi / 4)
    right = np.sin((pan + 1) * np.pi / 4)
    return np.stack([mono * left, mono * right], axis=1)


def _add(buf, start, sig):
    i = int(start * SR)
    if i >= len(buf):
        return
    n = min(len(sig), len(buf) - i)
    buf[i:i + n] += sig[:n]


def pad_note(freq, duration):
    t = _t(duration)
    sig = np.zeros_like(t)
    for detune in (-0.004, 0.0, 0.004):
        f = freq * (1 + detune)
        for harmonic, weight in ((1, 1.0), (2, 0.35), (3, 0.18), (5, 0.06)):
            sig += weight * np.sin(2 * np.pi * f * harmonic * t + detune * 40)
    attack, release = 0.7, 0.9
    env = np.minimum(1.0, t / attack) * np.minimum(1.0, (duration - t) / release)
    return sig * env * 0.05


def pluck(freq, duration=0.9, tau=0.28):
    t = _t(duration)
    sig = np.zeros_like(t)
    for harmonic, weight, decay in ((1, 1.0, 1.0), (2, 0.42, 0.7), (3, 0.2, 0.5), (4, 0.09, 0.35)):
        sig += weight * np.sin(2 * np.pi * freq * harmonic * t) * np.exp(-t / (tau * decay))
    attack = np.minimum(1.0, t / 0.004)
    return sig * attack * 0.16


def bass_note(freq, duration=0.9):
    t = _t(duration)
    sig = np.sin(2 * np.pi * freq * t) + 0.3 * np.sin(2 * np.pi * freq * 2 * t)
    return sig * np.exp(-t / 0.42) * np.minimum(1.0, t / 0.01) * 0.2


def hat(rng):
    t = _t(0.06)
    noise = rng.standard_normal(len(t))
    noise = np.diff(noise, prepend=0.0)  # срезает низкие частоты
    return noise * np.exp(-t / 0.012) * 0.03


def tick():
    """Тихий щелчок касания."""
    t = _t(0.09)
    freq = 1500 + 900 * np.exp(-t / 0.012)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * np.exp(-t / 0.022) * 0.22


def bell(freq, duration=1.3):
    t = _t(duration)
    sig = np.sin(2 * np.pi * freq * t) + 0.32 * np.sin(2 * np.pi * freq * 2.76 * t) * np.exp(-t / 0.25) \
        + 0.12 * np.sin(2 * np.pi * freq * 5.4 * t) * np.exp(-t / 0.12)
    return sig * np.exp(-t / 0.55) * np.minimum(1.0, t / 0.004) * 0.16


def _reverb(rng, wet):
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    out = []
    for _ in range(2):
        ir = rng.standard_normal(n) * np.exp(-t / 0.4)
        k = 24
        ir = np.convolve(ir, np.ones(k) / k, mode='same')  # смягчает верх
        out.append(ir / np.sqrt(np.sum(ir ** 2)))
    size = 1 << int(np.ceil(np.log2(len(wet) + n)))
    result = np.zeros_like(wet)
    for ch in range(2):
        spec = np.fft.rfft(wet[:, ch], size) * np.fft.rfft(out[ch], size)
        result[:, ch] = np.fft.irfft(spec, size)[:len(wet)]
    return result


def _lowpass(x, cutoff):
    """Фильтр первого порядка через спектр: 1 / (1 + j f / fc)."""
    size = len(x)
    freqs = np.fft.rfftfreq(size, 1 / SR)
    response = 1.0 / (1.0 + 1j * freqs / cutoff)
    out = np.empty_like(x)
    for ch in range(x.shape[1]):
        out[:, ch] = np.fft.irfft(np.fft.rfft(x[:, ch]) * response, size)
    return out


def render(duration, taps=(), chimes=(), seed=7):
    """Стерео-звук длиной `duration` секунд. taps и chimes — времена звуков касаний и «цель достигнута»."""
    rng = np.random.default_rng(seed)
    n = int((duration + 1.6) * SR)
    dry = np.zeros((n, 2))
    wet = np.zeros((n, 2))
    bars = int(duration / (BEAT * 4)) + 2

    for bar in range(bars):
        bass, pad, arp = CHORDS[bar % len(CHORDS)]
        t0 = bar * BEAT * 4
        for note in pad:
            _add(wet, t0 - 0.2 if bar else t0, _stereo(pad_note(_hz(note), BEAT * 4 + 1.4), 0.0))
        _add(dry, t0, _stereo(bass_note(_hz(bass)), 0.0))
        _add(dry, t0 + BEAT * 2, _stereo(bass_note(_hz(bass)), 0.0) * 0.7)
        for i, idx in enumerate(ARP_PATTERN):
            start = t0 + i * BEAT / 2
            if start < BEAT:
                continue  # арпеджио входит со второй доли
            accent = 1.0 if i % 4 == 0 else 0.72
            pan = 0.4 if i % 2 else -0.4
            sig = _stereo(pluck(_hz(arp[idx]) * 2 if i % 2 else _hz(arp[idx])), pan) * accent
            _add(dry, start, sig)
            _add(wet, start, sig * 0.8)
            if start > 2.4 and i % 2:
                _add(dry, start, _stereo(hat(rng), 0.25))

    for when in taps:
        _add(dry, when, _stereo(tick(), 0.0))
    for when in chimes:
        for i, note in enumerate((84, 88, 91, 96)):
            _add(dry, when + i * 0.075, _stereo(bell(_hz(note)), 0.0))
            _add(wet, when + i * 0.075, _stereo(bell(_hz(note)), 0.0) * 0.6)

    mix = dry + 0.35 * _reverb(rng, wet) + 0.25 * wet
    mix = mix[:int(duration * SR)]
    t = np.arange(len(mix)) / SR
    fade = np.minimum(1.0, t / 0.6) * np.minimum(1.0, (duration - t) / 1.8)
    mix = mix * fade[:, None]
    mix = np.tanh(mix * 1.6) / 1.6  # мягкое ограничение пиков
    mix = _lowpass(mix, 9000)  # снимает резкость верха
    peak = np.abs(mix).max()
    mix *= 0.5 / max(peak, 1e-6)  # музыка тихая, под звуки интерфейса
    return mix.astype(np.float32)


def write_wav(path, samples):
    data = (np.clip(samples, -1, 1) * 32767).astype('<i2')
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
