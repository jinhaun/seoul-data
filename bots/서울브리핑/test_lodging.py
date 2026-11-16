"""숙박 집계와 독립 검증: 누락·변화 없음·변조·여러 줄 업소명 회귀 확인."""
import copy
import csv
import json
import tempfile
import unittest
from datetime import date, timedelta
from pathlib import Path
from unittest.mock import patch

import brief
import verify_brief

REF = date(2026, 11, 16)
LOG_FIELDS = ["날짜", "종류", "전체", "영업중", "신규", "변경", "삭제"]
CHANGE_FIELDS = ["구분", "업소명", "자치구"]


class LodgingChecks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.data = Path(self.tmp.name)
        for module in (brief, verify_brief):
            context = patch.object(module, "DATA", self.data)
            context.start()
            self.addCleanup(context.stop)

    def write_csv(self, path, fields, records):
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", encoding="utf-8-sig", newline="") as f:
            writer = csv.DictWriter(f, fields)
            writer.writeheader()
            writer.writerows(records)

    def logs(self, *entries):
        self.write_csv(self.data / "status" / "숙박기록.csv", LOG_FIELDS,
                       [dict(zip(LOG_FIELDS, [str(day), kind, "10", "8", str(n), str(c), str(d)]))
                        for day, kind, n, c, d in entries])

    def changes(self, kind, records):
        self.write_csv(self.data / "lodging" / "changes" / "2026-11" / f"{REF}_{kind}.csv",
                       CHANGE_FIELDS, [dict(zip(CHANGE_FIELDS, values)) for values in records])

    def render(self):
        report = brief.lodging(REF)
        text = brief.lodging_text(report)
        body = {"blocks": [{"type": "section", "text": {"type": "mrkdwn",
                "text": f"*🏨 ④ 서울 숙박업소 변화* ({REF} 수집)\n{text}"}}]}
        return report, text, body

    def verify(self, report, text, body):
        return verify_brief.verify_lodging(REF, report, text, json.dumps(body, ensure_ascii=False))

    def test_missing_is_not_zero_or_unchanged(self):
        report, text, body = self.render()
        self.assertEqual([x["건수"] for x in report["종류"]], [None] * 3)
        self.assertEqual(text.count("오늘 자료 없음"), 3)
        self.assertNotIn("변화 없음", text)
        self.assertEqual(self.verify(report, text, body), [])

    def test_only_requested_date_counts(self):
        self.logs((REF - timedelta(days=1), "호텔", 9, 1, 0),
                  (REF + timedelta(days=1), "외국인민박", 1, 0, 0))
        self.assertTrue(all(x["건수"] is None for x in brief.lodging(REF)["종류"]))

    def test_successful_unchanged_needs_no_changes_file(self):
        self.logs(*[(REF, kind, 0, 0, 0) for kind in ("호텔", "외국인민박", "숙박업")])
        report, text, body = self.render()
        self.assertEqual(text.count("변화 없음"), 3)
        self.assertEqual(self.verify(report, text, body), [])

    def test_counts_examples_multiline_and_missing_district(self):
        self.logs((REF, "호텔", 3, 1, 1))
        self.changes("호텔", [("신규", '서울,\n"쉼" <숙소>', "종로구"),
                              ("변경", "변경 업소", "중구"),
                              ("신규", "두 번째", ""),
                              ("신규", "세 번째", "마포구"),
                              ("삭제", "삭제 업소", "용산구")])
        report, text, body = self.render()
        hotel = report["종류"][0]
        self.assertEqual(hotel["건수"], {"신규": 3, "변경": 1, "삭제": 1})
        self.assertEqual(len(hotel["신규업소"]), 2)
        self.assertIn('&lt;숙소&gt;', text)
        self.assertIn("두 번째(자치구 미상)", text)
        self.assertNotIn("세 번째", text)
        self.assertEqual(self.verify(report, text, body), [])

    def test_changed_log_without_original_stops(self):
        self.logs((REF, "호텔", 1, 0, 0))
        with self.assertRaisesRegex(ValueError, "불일치"):
            brief.lodging(REF)

    def test_log_and_original_mismatch_stops(self):
        self.logs((REF, "호텔", 0, 0, 0))
        self.changes("호텔", [("신규", "예시", "중구")])
        with self.assertRaisesRegex(ValueError, "불일치"):
            brief.lodging(REF)

    def test_unknown_change_category_stops(self):
        self.logs((REF, "호텔", 1, 0, 0))
        self.changes("호텔", [("알수없음", "예시", "중구")])
        with self.assertRaisesRegex(ValueError, "구분"):
            brief.lodging(REF)

    def test_tampered_count_and_name_are_rejected(self):
        self.logs((REF, "호텔", 1, 0, 0))
        self.changes("호텔", [("신규", "정확한 업소", "중구")])
        report, text, body = self.render()
        for field in ("건수", "신규업소"):
            changed = copy.deepcopy(report)
            if field == "건수":
                changed["종류"][0][field]["신규"] = 10
            else:
                changed["종류"][0][field][0]["업소명"] = "지어낸 업소"
            self.assertTrue(self.verify(changed, text, body))

    def test_tampered_display_and_removed_section_are_rejected(self):
        self.logs((REF, "호텔", 1, 0, 0))
        self.changes("호텔", [("신규", "정확한 업소", "중구")])
        report, text, body = self.render()
        modified = copy.deepcopy(body)
        modified["blocks"][0]["text"]["text"] = modified["blocks"][0]["text"]["text"].replace("신규 1", "신규 9")
        self.assertTrue(self.verify(report, text, modified))
        self.assertTrue(self.verify(report, text, {"blocks": []}))

    def test_original_changed_after_report_is_rejected(self):
        self.logs((REF, "호텔", 1, 0, 0))
        self.changes("호텔", [("신규", "원래 업소", "중구")])
        report, text, body = self.render()
        self.changes("호텔", [("신규", "다른 업소", "중구"), ("신규", "추가", "마포구")])
        self.assertTrue(self.verify(report, text, body))


if __name__ == "__main__":
    unittest.main()

