import csv
import importlib.util
import tempfile
import unittest
from datetime import date
from pathlib import Path

SPEC = importlib.util.spec_from_file_location('patterns', Path(__file__).resolve().parents[1] / 'scripts/build_visit_patterns.py')
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class PatternsTest(unittest.TestCase):
    def test_equal_day_weight_duplicates_zero_missing_and_partial_day(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            folder = root / 'data/realtime/2026-11'
            folder.mkdir(parents=True)
            fields = ['장소', '인구기준시각', '인구_최소', '인구_최대', '수집시각']
            rows = [dict(zip(fields, ['성수카페거리', '2026-11-07 14:00', 100, 100, '2026-11-07 14:31'])),
                    dict(zip(fields, ['성수카페거리', '2026-11-07 14:30', 300, 300, '2026-11-07 15:01']))]
            # 정확히 같은 관측을 복제해도 날짜 비중은 늘지 않아야 합니다.
            rows += [rows[0].copy()] * 3
            samples = [('2026-11-07.csv', rows),
                       ('2026-11-14.csv', [dict(zip(fields, ['성수카페거리', '2026-11-14 14:00', 1000, 1000, '']))]),
                       ('2026-11-21.csv', [dict(zip(fields, ['성수카페거리', '2026-11-21 14:00', 0, 0, ''])),
                                          dict(zip(fields, ['성수카페거리', '2026-11-21 15:00', '', '', '']))]),
                       ('2026-11-26.csv', [dict(zip(fields, ['성수카페거리', '2026-11-26 14:00', 999999, 999999, '']))])]
            for name, data in samples:
                with (folder/name).open('w', encoding='utf-8-sig', newline='') as f:
                    writer = csv.DictWriter(f, fieldnames=fields)
                    writer.writeheader()
                    writer.writerows(data)
            result = module.aggregate(root, date(2026, 11, 26))
            cell = result['places'][0]['grid'][5][14]
            self.assertEqual(cell[:2], [400.0, 3])  # (200 + 1000 + 0) / 3
            self.assertEqual(result['period']['expected_dates'][5], 4)
            self.assertEqual(result['places'][0]['grid'][5][15][:2], [None, 0])
            self.assertIsNone(result['places'][0]['daily'][5]['mean'])
            self.assertEqual(result['quality']['duplicate_rows'], 3)
            self.assertEqual(result['quality']['invalid_rows'], 1)
            module.save_outputs(result, root)
            self.assertTrue((root/'site/visit-patterns.json').exists())

    def test_missing_place_and_conflicting_duplicate_keep_earliest_value(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            folder = root/'data/realtime/2026-11'
            folder.mkdir(parents=True)
            meta = root/'data/meta'
            meta.mkdir(parents=True)
            (meta/'장소_121곳.csv').write_text('장소,분류\n천호역,역\n성수카페거리,거리\n', encoding='utf-8-sig')
            with (folder/'2026-11-07.csv').open('w', encoding='utf-8-sig', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['장소', '인구기준시각', '인구_최소', '인구_최대', '수집시각'])
                writer.writerow(['천호역', '2026-11-07 00:00', 900, 1100, '2026-11-07 00:40'])
                writer.writerow(['천호역', '2026-11-07 00:00', 100, 200, '2026-11-07 00:30'])
                writer.writerow(['천호역', '2026-10-26 23:30', 999999, 999999, ''])
                writer.writerow(['천호역', '2026-11-07 01:00', -1, 200, ''])
            result = module.aggregate(root, date(2026, 11, 26))
            by_place = {p['name']: p for p in result['places']}
            self.assertEqual(by_place['천호역']['grid'][5][0][:4], [150, 1, 100, 200])
            self.assertEqual(by_place['성수카페거리']['grid'][5][0][:2], [None, 0])
            self.assertEqual(result['quality']['conflicting_duplicates'], 1)
            self.assertEqual(result['quality']['invalid_rows'], 1)
            module.save_outputs(result, root)
            with (root/'data/analysis/방문시간_요일시간_최근30일.csv').open(encoding='utf-8-sig', newline='') as f:
                rows = list(csv.DictReader(f))
            absent = next(r for r in rows if r['장소']=='성수카페거리' and r['요일']=='토' and r['시간']=='0')
            self.assertEqual((absent['평균인구_명'], absent['관측날짜수'], absent['누락날짜수']), ('', '0', '4'))

    def test_daily_average_requires_24_hours_and_keeps_bounds(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            folder = root/'data/realtime/2026-11'
            folder.mkdir(parents=True)
            with (folder/'2026-11-07.csv').open('w', encoding='utf-8-sig', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['장소', '인구기준시각', '인구_최소', '인구_최대'])
                for h in range(24):
                    writer.writerow(['천호역', f'2026-11-07 {h:02d}:00', 100, 200])
            result = module.aggregate(root, date(2026, 11, 26))
            place = result['places'][0]
            self.assertEqual(place['daily'][5]['mean'], 150)
            self.assertEqual(place['daily'][5]['n'], 1)
            self.assertEqual(place['grid'][5][14][:4], [150, 1, 100, 200])


if __name__ == '__main__':
    unittest.main()
