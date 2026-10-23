"""Проверки монтажёра ролика: python3 -m unittest discover -s Tools/AppPreview"""
import unittest
from pathlib import Path

import compose
import overlay
import scenes

RESOURCES = Path(__file__).resolve().parents[2] / 'Resources'


def fake_states(plan, step=0.1):
    """plan: [(время начала, номер метки)] -> состояния кадров с шагом step."""
    states = []
    for i in range(int((plan[-1][0] + 2.0) / step)):
        t = round(i * step, 6)
        number = [n for start, n in plan if start <= t][-1]
        states.append((t, None, None, None, number))
    return states


class SceneTests(unittest.TestCase):
    def test_marker_boundaries_found_in_order(self):
        plan = [(0, 1), (5, 2), (9, 3), (14, 4), (17, 5), (22, 6), (27, 7)]
        self.assertEqual(scenes.find_marker_boundaries(fake_states(plan)), [5.0, 9.0, 14.0, 17.0, 22.0, 27.0])

    def test_marker_boundaries_missing_scene(self):
        plan = [(0, 1), (5, 2), (9, 3), (14, 4), (17, 5), (22, 6)]
        self.assertIsNone(scenes.find_marker_boundaries(fake_states(plan)))

    def test_single_glitch_frame_is_not_a_scene(self):
        plan = [(0, 1), (5, 2), (9, 3), (14, 4), (17, 5), (22, 6), (27, 7)]
        states = fake_states(plan)
        states[10] = (states[10][0], None, None, None, 6)  # один кадр с чужим номером
        self.assertEqual(scenes.find_marker_boundaries(states)[0], 5.0)

    def test_timeline_respects_scene_limits(self):
        # Кадры идут ровно раз в 0.05 с, все сцены длинные: каждая сцена обрезается до максимума
        pts = [i * 0.05 for i in range(1, 900)]
        boundaries = [6, 12, 18, 24, 30, 36]
        keys, total, starts = scenes.build_timeline(pts, boundaries)
        self.assertEqual(len(starts), 7)
        self.assertLessEqual(total, sum(hi for _, hi in scenes.SCENE_LIMITS) + 1e-6)
        self.assertEqual(starts[1], scenes.SCENE_LIMITS[0][0])
        times = [t for t, _ in keys]
        self.assertEqual(times, sorted(times))

    def test_idle_screen_is_shortened_and_never_below_minimum(self):
        # Экран после границы почти не меняется: сцена не короче минимума и не длиннее максимума
        pts = [0.0, 5.0, 5.05, 12.0, 12.05, 20.0, 28.0, 35.0, 42.0, 49.0, 56.0]
        keys, total, starts = scenes.build_timeline(pts, [5.0, 12.0, 20.0, 28.0, 35.0, 42.0])
        for j in range(1, 7):
            length = (starts[j + 1] if j < 6 else total) - starts[j]
            lo, hi = scenes.SCENE_LIMITS[j]
            self.assertGreaterEqual(length, lo - 1e-6)
            self.assertLessEqual(length, hi + 1e-6)


class OverlayTests(unittest.TestCase):
    def test_captions_exist_in_every_language(self):
        for lang in ('ru', 'en', 'hy'):
            texts = compose.localized_captions(RESOURCES, lang)
            self.assertEqual(len(texts), len(compose.CAPTIONS))
            if lang != 'ru':
                for source, text in zip(compose.CAPTIONS, texts):
                    self.assertNotEqual(source, text, f'{lang}: нет перевода «{source}»')

    def test_captions_fit_in_band(self):
        band_height = overlay.BAND[1] - overlay.BAND[0]
        for lang in ('ru', 'en', 'hy'):
            for text in compose.localized_captions(RESOURCES, lang):
                caption = overlay.Caption(text)
                self.assertLessEqual(caption.height, band_height, f'{lang}: «{text}» не помещается в полосу')
                self.assertLessEqual(caption.width, overlay.WIDTH - 40, f'{lang}: «{text}» шире экрана')

    def test_armenian_uses_armenian_font(self):
        runs = overlay._runs('SMS-ներն ու սքրինշոթները')
        self.assertTrue(any(arm for arm, _ in runs))
        self.assertTrue(any(not arm for arm, _ in runs))


if __name__ == '__main__':
    unittest.main()
