"""Разбор записи симулятора: время кадров, границы сцен по подписям, раскладка времени для монтажа."""
import re
import subprocess

import numpy as np

# Кадры записи приходят только при изменении экрана; промежуток короче этого считаем анимацией и смешиваем кадры
GAP_BLEND = 0.13

# Разметка записи (координаты на уменьшенной в 4 раза записи 330x717).
# Новая запись: в полосе над экраном тонкая серая метка, её длина (18 точек на номер сцены) говорит, какая сцена идёт.
# Старая запись: лаймовая плашка с текстом подписи; по ней сцены тоже находятся, но менее надёжно.
ANALYSIS_W, ANALYSIS_H = 330, 717
BAND_ROWS = (50, 105)
LIME = (196, 241, 49)
MARKER_ROWS = (72, 76)
MARKER_X0, MARKER_PER_SCENE = 12, 18
SCENE_COUNT = 7

# Сколько секунд занимает каждая из семи сцен в готовом ролике: (минимум, максимум).
# Пауза экрана длиннее минимума сжимается, но сцена не короче минимума; первая сцена (обзор) без движения, ей нужен ровный срок.
SCENE_LIMITS = [(2.4, 2.4), (3.0, 4.6), (3.5, 5.0), (2.4, 3.4), (2.8, 4.2), (3.4, 4.8), (2.8, 3.6)]
IDLE_CAP = 1.0
MIN_IDLE_CAP = 0.25


def probe_pts(ffmpeg, src):
    """Время кадров записи в порядке декодирования и список номеров кадров с растущим временем.

    Симулятор изредка выдаёт кадры с временем «назад»; такие кадры отбрасываем, как это делает сам ffmpeg."""
    out = subprocess.run([ffmpeg, '-hide_banner', '-i', src, '-an', '-vf', 'showinfo', '-f', 'null', '-'],
                         capture_output=True, text=True).stderr
    raw = [float(m) for m in re.findall(r'pts_time:([0-9.]+)', out)]
    kept = []
    last = -1.0
    for i, p in enumerate(raw):
        if p > last:
            kept.append(i)
            last = p
    return raw, kept


def caption_states(ffmpeg, src, pts, kept):
    """Для каждого оставленного кадра: (время, x0, x1, высота плашки, номер сцены по метке).

    Плашка: x0 = None, если лаймовой плашки нет. Номер сцены: 0, если метки нет."""
    proc = subprocess.Popen(
        [ffmpeg, '-hide_banner', '-loglevel', 'error', '-i', src, '-an', '-fps_mode', 'passthrough',
         '-vf', f'scale={ANALYSIS_W}:{ANALYSIS_H}', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    size = ANALYSIS_W * ANALYSIS_H * 3
    wanted = set(kept)
    states = []
    for i in range(len(pts)):
        buf = proc.stdout.read(size)
        if len(buf) < size:
            break
        if i not in wanted:
            continue
        frame = np.frombuffer(buf, np.uint8).reshape(ANALYSIS_H, ANALYSIS_W, 3)
        marker = _marker_scene(frame)
        band = frame[BAND_ROWS[0]:BAND_ROWS[1]].astype(int)
        lime = ((abs(band[:, :, 0] - LIME[0]) < 30) & (abs(band[:, :, 1] - LIME[1]) < 25) & (band[:, :, 2] < 110))
        if lime.sum() > 200:
            cols = np.where(lime.any(axis=0))[0]
            rows = np.where(lime.any(axis=1))[0]
            states.append((pts[i], int(cols.min()), int(cols.max()), int(rows.max() - rows.min()), marker))
        else:
            states.append((pts[i], None, None, None, marker))
    proc.stdout.close()
    proc.wait()
    return states


def _marker_scene(frame):
    """Номер сцены по длине серой метки в полосе над экраном; 0, если метки нет."""
    strip = frame[MARKER_ROWS[0]:MARKER_ROWS[1]].astype(int).mean(axis=(0, 2))
    on = strip > 50
    if not on[MARKER_X0 - 4:MARKER_X0 + 6].any():
        return 0
    start = MARKER_X0 - 4 + int(np.argmax(on[MARKER_X0 - 4:MARKER_X0 + 6]))
    length = 0
    while start + length < len(on) and on[start + length]:
        length += 1
    number = int(round(length / MARKER_PER_SCENE))
    return number if 1 <= number <= SCENE_COUNT else 0


def find_marker_boundaries(states):
    """Моменты, когда метка сцены меняется на 2, 3, ... 7. Возвращает 6 времён или None, если метки нет или она неполная."""
    found = []
    for number in range(2, SCENE_COUNT + 1):
        when = None
        for i, state in enumerate(states):
            if state[4] != number:
                continue
            if i + 1 >= len(states) or states[i + 1][4] == number:
                when = state[0]
                break
        if when is None or (found and when <= found[-1]):
            return None
        found.append(when)
    return found


def _same(a, b, tol=8):
    if a is None or b is None:
        return a is None and b is None
    return all(abs(x - y) <= tol for x, y in zip(a, b))


def find_boundaries(states, expected=6):
    """Моменты смены подписи. Возвращает список из `expected` времён или None, если разобрать не удалось."""
    runs = []  # [состояние, начало]
    for t, x0, x1, h, _ in states:
        st = None if x0 is None else (x0, x1, h)
        if runs and _same(runs[-1][0], st):
            continue
        runs.append([st, t])
    end = states[-1][0]
    for i, run in enumerate(runs):
        run.append((runs[i + 1][1] if i + 1 < len(runs) else end) - run[1])  # длительность

    # Короткие состояния плашки (качание при показе и скрытии экранов) отбрасываем, промежутки «плашки нет» оставляем
    kept = []
    for st, t0, dur in runs:
        if st is not None and dur < 0.45:
            continue
        if kept and _same(kept[-1][0], st):
            kept[-1][2] += dur
            continue
        kept.append([st, t0, dur])

    boundaries = []
    for i in range(1, len(kept)):
        cur = kept[i]
        if cur[0] is None:
            continue
        prev = kept[i - 1]
        if prev[0] is None:
            before = kept[i - 2] if i >= 2 else None
            if before is None or before[0] is None:
                continue
            boundaries.append((prev[1] + cur[1]) / 2)
        else:
            boundaries.append(cur[1])
    return boundaries if len(boundaries) == expected else None


def nominal_boundaries(end, expected=6):
    """Запасной вариант, если подписи разобрать не удалось: сцены поровну от начала движения."""
    start = end * 0.18
    step = (end - start) / expected
    return [start + step * i for i in range(expected)]


def _scene_frames(pts, a, b):
    """Индексы кадров сцены [a, b): сначала кадр, видимый в момент a, потом новые."""
    first = 0
    for k, p in enumerate(pts):
        if p <= a:
            first = k
        else:
            break
    return [first] + [k for k, p in enumerate(pts) if a < p < b]


def _scene_gaps(pts, idx, a, b):
    """Промежутки между кадрами сцены, включая последний до границы: [(кадр, длина)]."""
    stamps = [max(pts[idx[0]], a)] + [pts[k] for k in idx[1:]] + [b]
    return [(idx[i], stamps[i + 1] - stamps[i]) for i in range(len(idx))]


def _length(gaps, cap):
    return sum(min(g, cap) for _, g in gaps)


def build_timeline(pts, boundaries):
    """Раскладка кадров записи по времени ролика.

    Возвращает ([(время ролика, номер кадра записи)], общая длина, время начала каждой сцены).
    Кадр показывается до следующей записи списка; если промежуток между двумя соседними короче GAP_BLEND,
    при отрисовке кадры плавно смешиваются.
    """
    ends = list(boundaries) + [pts[-1] + 0.3]
    starts = [0.0] + list(boundaries)
    keys = []
    scene_starts = []
    now = 0.0
    for j, (a, b) in enumerate(zip(starts, ends)):
        lo, hi = SCENE_LIMITS[j]
        idx = _scene_frames(pts, a, b)
        scene_starts.append(now)

        if j == 0:
            # Обзор: экран неподвижен, держим один кадр ровно положенное время
            keys.append((now, idx[0]))
            now += lo
            continue

        gaps = _scene_gaps(pts, idx, a, b)
        cap = IDLE_CAP
        if _length(gaps, cap) > hi:
            low, high = MIN_IDLE_CAP, cap
            for _ in range(24):
                mid = (low + high) / 2
                if _length(gaps, mid) > hi:
                    high = mid
                else:
                    low = mid
            cap = low

        length = min(_length(gaps, cap), hi)
        t = now
        for k, g in gaps:
            if t >= now + length:
                break
            keys.append((t, k))
            t += min(g, cap)
        now += max(length, lo)
    return keys, now, scene_starts
