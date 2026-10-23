"""Анимированные накладки ролика: подписи, касания, полоса прогресса. Рисуем только графику поверх записи приложения."""
import math
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

WIDTH, HEIGHT = 886, 1920
FONT_DIR = Path(__file__).parent / 'fonts'

# Полоса подписи в записи (1320x2868 -> 886x1920): подпись приложения закрашиваем и рисуем свою
BAND = (119, 276)
BAND_COLOR = (17, 16, 19)
LIME = (196, 241, 49)
INK = (17, 18, 14)

# Центры значков вкладок и высота панели вкладок
TAB_X = [0.114, 0.307, 0.499, 0.693, 0.886]
TAB_Y = 1802


def clamp(x, lo=0.0, hi=1.0):
    return max(lo, min(hi, x))


def ease_out_cubic(p):
    return 1 - (1 - p) ** 3


def ease_out_back(p, s=1.9):
    p = p - 1
    return 1 + (s + 1) * p ** 3 + s * p ** 2


def ease_in_out(p):
    return p * p * (3 - 2 * p)


# ---------- Шрифты и текст ----------

_fonts = {}


def _font(armenian, size):
    key = (armenian, size)
    if key not in _fonts:
        name = 'NotoSansArmenian-Bold.ttf' if armenian else 'NotoSans-Bold.ttf'
        _fonts[key] = ImageFont.truetype(str(FONT_DIR / name), size)
    return _fonts[key]


def _runs(text):
    """Делит строку на куски: армянские буквы рисуем армянским шрифтом, остальное основным."""
    runs = []
    for ch in text:
        arm = '԰' <= ch <= '֏'
        if ch in ' .,!?:;-–—()«»"\'0123456789%+' and runs:
            arm = runs[-1][0]
        if runs and runs[-1][0] == arm:
            runs[-1][1] += ch
        else:
            runs.append([arm, ch])
    return runs


def text_width(text, size):
    return sum(_font(arm, size).getlength(chunk) for arm, chunk in _runs(text))


def draw_text(draw, xy, text, size, fill):
    x, y = xy
    for arm, chunk in _runs(text):
        font = _font(arm, size)
        draw.text((x, y), chunk, font=font, fill=fill)
        x += font.getlength(chunk)


def wrap(text, size, max_width):
    """Делит подпись на одну или две строки."""
    words = text.split()
    if text_width(text, size) <= max_width:
        return [text]
    best = None
    for i in range(1, len(words)):
        left, right = ' '.join(words[:i]), ' '.join(words[i:])
        width = max(text_width(left, size), text_width(right, size))
        if best is None or width < best[0]:
            best = (width, [left, right])
    return best[1] if best and best[0] <= max_width else None


class Caption:
    """Подпись сцены: плашка и слова отдельными спрайтами, чтобы слова появлялись по очереди."""

    SS = 3  # во сколько раз рисуем крупнее для гладких краёв

    def __init__(self, text):
        max_width = WIDTH - 2 * 30 - 2 * 38
        size = 42
        lines = None
        while lines is None or len(lines) > 2:
            lines = wrap(text, size, max_width)
            if lines is None:
                size -= 2
        self.size = size
        line_h = int(size * 1.32)
        pad_x, pad_y = 38, 22
        width = int(max(text_width(line, size) for line in lines)) + 2 * pad_x
        height = line_h * len(lines) + 2 * pad_y
        self.width, self.height = width, height

        ss = self.SS
        pill = Image.new('RGBA', (width * ss, height * ss), (0, 0, 0, 0))
        ImageDraw.Draw(pill).rounded_rectangle((0, 0, width * ss - 1, height * ss - 1), radius=min(height, 78) * ss // 2,
                                               fill=LIME + (255,))
        self.pill = pill.resize((width, height), Image.LANCZOS)

        # Слова: каждое отдельным спрайтом; (спрайт, x, y) относительно плашки
        self.words = []
        for row, line in enumerate(lines):
            line_w = text_width(line, size)
            x = (width - line_w) / 2
            for word in line.split(' '):
                w = text_width(word, size)
                spr = Image.new('RGBA', (int(w) + 8, line_h + 8), (0, 0, 0, 0))
                draw_text(ImageDraw.Draw(spr), (4, 4), word, size, INK + (255,))
                self.words.append((spr, int(x) - 4, pad_y + row * line_h - 4 + int(size * 0.06)))
                x += w + text_width(' ', size)

    def render(self, tt, tleft):
        """Картинка подписи в момент tt секунд от начала сцены; tleft — сколько секунд осталось до конца сцены.
        Возвращает (RGBA-спрайт, смещение по x и y относительно центра полосы) или None."""
        p_in = clamp((tt - 0.02) / 0.45)
        if p_in <= 0:
            return None
        scale = 0.88 + 0.12 * ease_out_back(p_in)
        alpha = clamp(p_in * 5.0)
        rise = (1 - ease_out_cubic(p_in)) * 28
        if tleft < 0.22:
            k = clamp(tleft / 0.22)
            alpha *= k
            rise = -(1 - k) * 14

        pad = 4
        canvas = Image.new('RGBA', (self.width + 2 * pad, self.height + 2 * pad), (0, 0, 0, 0))
        canvas.alpha_composite(self.pill, (pad, pad))
        for n, (spr, x, y) in enumerate(self.words):
            wp = clamp((tt - 0.07 - 0.045 * n) / 0.28)
            if wp <= 0:
                continue
            e = ease_out_cubic(wp)
            moved = spr.copy()
            moved.putalpha(spr.split()[3].point(lambda v, e=e: int(v * e)))
            canvas.alpha_composite(moved, (pad + x, pad + y + int((1 - e) * 14)))

        if abs(scale - 1) > 0.002:
            canvas = canvas.resize((max(1, int(canvas.width * scale)), max(1, int(canvas.height * scale))), Image.BILINEAR)
        if alpha < 0.999:
            canvas.putalpha(canvas.split()[3].point(lambda v: int(v * alpha)))
        return canvas, rise


def blit(frame, sprite, cx, cy):
    """Накладывает RGBA-спрайт центром в (cx, cy) на кадр (numpy uint8, H x W x 3)."""
    arr = np.asarray(sprite)
    h, w = arr.shape[:2]
    x0, y0 = int(cx - w / 2), int(cy - h / 2)
    fx0, fy0 = max(0, x0), max(0, y0)
    fx1, fy1 = min(frame.shape[1], x0 + w), min(frame.shape[0], y0 + h)
    if fx1 <= fx0 or fy1 <= fy0:
        return
    s = arr[fy0 - y0:fy1 - y0, fx0 - x0:fx1 - x0].astype(np.float32)
    a = s[:, :, 3:4] / 255.0
    region = frame[fy0:fy1, fx0:fx1].astype(np.float32)
    frame[fy0:fy1, fx0:fx1] = (region * (1 - a) + s[:, :, :3] * a + 0.5).astype(np.uint8)


def clear_band(frame):
    frame[BAND[0]:BAND[1]] = BAND_COLOR


def draw_caption(frame, caption, tt, tleft):
    rendered = caption.render(tt, tleft)
    if rendered is None:
        return
    sprite, rise = rendered
    # Рисуем только в полосе подписи (с небольшим запасом): иначе свечение закроет шапку экрана
    top = BAND[0] - 6
    blit(frame[top:BAND[1] + 6], sprite, WIDTH / 2, (BAND[0] + BAND[1]) / 2 + rise - top)


# ---------- Касание ----------

def draw_tap(frame, tab, tt):
    """Точка касания на вкладке: диск и расходящееся кольцо. tab — номер вкладки 0..4, tt — секунды от касания."""
    if tt < 0 or tt > 0.8:
        return
    size = 300
    ss = 2
    img = Image.new('RGBA', (size * ss, size * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size * ss / 2

    disk_r = 38 * (0.55 + 0.45 * ease_out_cubic(clamp(tt / 0.16)))
    disk_a = 150 if tt < 0.22 else int(150 * clamp(1 - (tt - 0.22) / 0.28))
    if disk_a > 0:
        r = disk_r * ss
        d.ellipse((c - r, c - r, c + r, c + r), fill=(255, 255, 255, disk_a))

    p = clamp(tt / 0.62)
    ring_r = (40 + 84 * ease_out_cubic(p)) * ss
    ring_a = int(210 * (1 - p) ** 1.3)
    if ring_a > 0:
        width = max(2, int((7 - 5 * p) * ss))
        d.ellipse((c - ring_r, c - ring_r, c + ring_r, c + ring_r), outline=(255, 255, 255, ring_a), width=width)
    blit(frame, img.resize((size, size), Image.LANCZOS), WIDTH * TAB_X[tab], TAB_Y)


# ---------- Полоса прогресса ----------

def draw_progress(frame, t, scene_starts, total):
    """Сверху тонкие отрезки по числу сцен: пройденные заполнены, текущий заполняется."""
    n = len(scene_starts)
    ends = scene_starts[1:] + [total]
    left, right, gap, y0, y1 = 30, WIDTH - 30, 7, 14, 20
    seg_w = (right - left - gap * (n - 1)) / n
    ss = 3
    img = Image.new('RGBA', (WIDTH * ss, 10 * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(n):
        x0 = left + i * (seg_w + gap)
        x1 = x0 + seg_w
        d.rounded_rectangle((x0 * ss, 2 * ss, x1 * ss, 8 * ss), radius=3 * ss, fill=(255, 255, 255, 70))
        p = clamp((t - scene_starts[i]) / max(0.001, ends[i] - scene_starts[i]))
        if p > 0:
            d.rounded_rectangle((x0 * ss, 2 * ss, (x0 + seg_w * p) * ss, 8 * ss), radius=3 * ss, fill=LIME + (240,))
    blit(frame, img.resize((WIDTH, 10), Image.LANCZOS), WIDTH / 2, (y0 + y1) / 2)


def apply_fade(frame, t, total, fade_in=0.4, fade_out=0.7):
    k = clamp(t / fade_in) if t < fade_in else 1.0
    if t > total - fade_out:
        k = min(k, clamp((total - t) / fade_out))
    if k < 0.999:
        frame[:] = (frame.astype(np.float32) * ease_in_out(k)).astype(np.uint8)


def load_strings(path):
    """Читает Localizable.strings: {ключ: перевод}."""
    result = {}
    pattern = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')
    for line in Path(path).read_text(encoding='utf-8').splitlines():
        m = pattern.match(line)
        if m:
            unesc = lambda s: s.replace('\\"', '"').replace('\\n', '\n').replace('\\\\', '\\')
            result[unesc(m.group(1))] = unesc(m.group(2))
    return result
