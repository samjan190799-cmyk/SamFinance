"""Собирает ролик App Store (App Preview) из записи экрана симулятора.

Запись приходит с неровной частотой кадров и с простой подписью приложения. Здесь она превращается в ролик
886x1920, 30 кадров/с: паузы экрана сокращаются, кадры плавно смешиваются, подпись заменяется анимированной,
добавляются касания вкладок, полоса прогресса, плавное начало и конец и музыка. Движется только графика поверх
настоящей записи: показанные экраны и действия остаются теми, что есть в приложении.

    python3 compose.py --ffmpeg ffmpeg --raw raw/ru.mp4 --lang ru --resources ../../Resources --out preview/ru.mp4
"""
import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

import music
import overlay
import scenes

FPS = 30
BLEND_MAX_DIFF = 8.0
CAPTIONS = [
    'Весь учёт в одном месте',
    'Свои карты: листайте и настраивайте',
    'Цвет, узор и значок: оформите карту по-своему',
    'Копилки с планом накопления',
    'Цель достигнута!',
    'СМС и скриншоты сами становятся операциями',
    'Отчёты по дням и категориям',
]
# Какие сцены начинаются нажатием на вкладку: (номер сцены, номер вкладки)
TAPS = [(1, 1), (5, 2), (6, 4)]
CHIME_SCENE, CHIME_OFFSET = 4, 2.0


def localized_captions(resources, lang):
    if lang == 'ru':
        return list(CAPTIONS)
    strings = overlay.load_strings(Path(resources) / f'{lang}.lproj' / 'Localizable.strings')
    return [strings.get(text, text) for text in CAPTIONS]


def decoder(ffmpeg, src):
    return subprocess.Popen(
        [ffmpeg, '-hide_banner', '-loglevel', 'error', '-i', src, '-an', '-fps_mode', 'passthrough',
         '-vf', f'scale={overlay.WIDTH}:{overlay.HEIGHT}:flags=lanczos:in_color_matrix=bt709,format=rgb24',
         '-f', 'rawvideo', '-'],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)


def encoder(ffmpeg, audio, out):
    cmd = [ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
           '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{overlay.WIDTH}x{overlay.HEIGHT}', '-r', str(FPS), '-i', '-']
    if audio:
        cmd += ['-i', str(audio)]
    else:
        cmd += ['-f', 'lavfi', '-i', 'anullsrc=channel_layout=stereo:sample_rate=48000']
    cmd += ['-vf', 'scale=out_color_matrix=bt709:out_range=tv:flags=lanczos,format=yuv420p,setsar=1',
            '-c:v', 'libx264', '-profile:v', 'high', '-level', '4.0', '-b:v', '10M', '-maxrate', '12M', '-bufsize', '20M',
            '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709',
            '-c:a', 'aac', '-b:a', '256k', '-ar', '48000', '-ac', '2', '-shortest', '-movflags', '+faststart', str(out)]
    return subprocess.Popen(cmd, stdin=subprocess.PIPE)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ffmpeg', default='ffmpeg')
    ap.add_argument('--raw', required=True)
    ap.add_argument('--lang', required=True, choices=['ru', 'en', 'hy'])
    ap.add_argument('--resources', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--no-music', action='store_true')
    ap.add_argument('--frames-dir', help='сохранить контрольные кадры в эту папку')
    args = ap.parse_args()

    raw_pts, kept = scenes.probe_pts(args.ffmpeg, args.raw)
    pts = [raw_pts[i] for i in kept]  # время оставленных кадров; номер кадра ниже считается среди них
    states = scenes.caption_states(args.ffmpeg, args.raw, raw_pts, kept)
    boundaries = scenes.find_marker_boundaries(states)
    if boundaries is None:
        print('Метки сцен в записи нет, ищу границы по плашке подписи', file=sys.stderr)
        boundaries = scenes.find_boundaries(states)
    if boundaries is None:
        print('Подписи в записи разобрать не удалось, сцены делятся поровну', file=sys.stderr)
        boundaries = scenes.nominal_boundaries(pts[-1])
    print('границы сцен в записи:', [round(b, 2) for b in boundaries])

    keys, total, scene_starts = scenes.build_timeline(pts, boundaries)
    scene_ends = scene_starts[1:] + [total]
    print('длина ролика %.2f с, начала сцен %s' % (total, [round(s, 2) for s in scene_starts]))
    if not 15.5 <= total <= 29.8:
        sys.exit(f'Длина {total:.2f} с вне допустимых 15-30 с')

    captions = [overlay.Caption(text) for text in localized_captions(args.resources, args.lang)]
    tap_times = [(scene_starts[s] - 0.1, tab) for s, tab in TAPS]

    audio = None
    tmp = tempfile.TemporaryDirectory()
    if not args.no_music:
        audio = Path(tmp.name) / 'music.wav'
        music.write_wav(audio, music.render(total, taps=[t for t, _ in tap_times],
                                            chimes=[scene_starts[CHIME_SCENE] + CHIME_OFFSET]))

    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    dec = decoder(args.ffmpeg, args.raw)
    enc = encoder(args.ffmpeg, audio, args.out)
    frame_size = overlay.WIDTH * overlay.HEIGHT * 3

    source = {}  # номер оставленного кадра -> картинка; держим только нужные
    wanted = {raw: n for n, raw in enumerate(kept)}  # номер кадра в файле -> номер оставленного
    state = {'decoded': 0, 'next': 0}

    def read_up_to(index):
        while state['next'] <= index:
            buf = dec.stdout.read(frame_size)
            if len(buf) < frame_size:
                raise RuntimeError(f'Запись кончилась на кадре {state["decoded"]}')
            raw_index = state['decoded']
            state['decoded'] += 1
            if raw_index in wanted:
                source[wanted[raw_index]] = np.frombuffer(buf, np.uint8).reshape(overlay.HEIGHT, overlay.WIDTH, 3)
                state['next'] = wanted[raw_index] + 1
        for old in [k for k in source if k < index - 1]:
            del source[old]

    n_frames = int(round(total * FPS))
    ki = 0
    for i in range(n_frames):
        t = i / FPS
        while ki + 1 < len(keys) and keys[ki + 1][0] <= t:
            ki += 1
        t0, k0 = keys[ki]
        read_up_to(k0)
        base = source[k0]
        if ki + 1 < len(keys):
            t1, k1 = keys[ki + 1]
            if t1 - t0 <= scenes.GAP_BLEND + 1e-6 and k1 != k0:
                read_up_to(k1)
                # Смешиваем кадры только при небольшом движении; быстрый сдвиг дал бы двойное изображение
                diff = np.abs(base[::8, ::8, 1].astype(np.int16) - source[k1][::8, ::8, 1].astype(np.int16)).mean()
                if diff < BLEND_MAX_DIFF:
                    w = int(256 * (t - t0) / (t1 - t0))
                    base = ((base.astype(np.uint16) * (256 - w) + source[k1].astype(np.uint16) * w) >> 8).astype(np.uint8)
        frame = base.copy()

        scene = max(j for j, s in enumerate(scene_starts) if s <= t + 1e-9)
        overlay.clear_band(frame)
        overlay.draw_caption(frame, captions[scene], t - scene_starts[scene], scene_ends[scene] - t)
        for when, tab in tap_times:
            overlay.draw_tap(frame, tab, t - when)
        overlay.draw_progress(frame, t, scene_starts, total)
        overlay.apply_fade(frame, t, total)
        enc.stdin.write(frame.tobytes())

        if args.frames_dir and i % 15 == 0:
            from PIL import Image
            Path(args.frames_dir).mkdir(parents=True, exist_ok=True)
            Image.fromarray(frame).save(Path(args.frames_dir) / f'{args.lang}_{i:04d}.jpg', quality=88)

    enc.stdin.close()
    enc.wait()
    dec.stdout.close()
    dec.terminate()
    dec.wait()
    try:
        tmp.cleanup()
    except OSError:
        pass
    if enc.returncode != 0:
        sys.exit('ffmpeg не смог собрать ролик')
    print('готово:', args.out)


if __name__ == '__main__':
    main()
