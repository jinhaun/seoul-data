"""실제 관측을 날짜별로 같은 비중으로 집계합니다. 외부 통신·인증값은 사용하지 않습니다."""
import argparse
import csv
import json
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from statistics import fmean

WEEKDAYS = ['월', '화', '수', '목', '금', '토', '일']


def read_csv(path):
    with path.open(encoding='utf-8-sig', newline='') as handle:
        yield from csv.DictReader(handle)


def aggregate(source_root, as_of, days=30):
    end = as_of - timedelta(days=1)
    start = as_of - timedelta(days=days)
    dates = [start + timedelta(days=i) for i in range(days)]
    expected = [sum(d.weekday() == w for d in dates) for w in range(7)]
    places = {}
    meta = source_root / 'data/meta/장소_121곳.csv'
    if meta.exists():
        places = {r['장소']: r.get('분류', '') for r in read_csv(meta) if r.get('장소')}
    instants = {}
    quality = dict(source_rows=0, invalid_rows=0, duplicate_rows=0, conflicting_duplicates=0)
    files = sorted((source_root / 'data/realtime').glob('*/*.csv'))
    used_files = []
    for path in files:
        if not (start.isoformat() <= path.stem <= end.isoformat()):
            continue
        used_files.append(path.relative_to(source_root).as_posix())
        for row in read_csv(path):
            quality['source_rows'] += 1
            try:
                stamp = datetime.strptime(row['인구기준시각'], '%Y-%m-%d %H:%M')
                if not start <= stamp.date() <= end:
                    continue
                place = row['장소'].strip()
                low, high = int(row['인구_최소']), int(row['인구_최대'])
                if not place or low < 0 or high < low:
                    raise ValueError('잘못된 인구 범위')
            except (ValueError, KeyError, TypeError):
                quality['invalid_rows'] += 1
                continue
            places.setdefault(place, '')
            key = (place, stamp)
            values = (low, high)
            collected = row.get('수집시각', '')
            if key in instants:
                quality['duplicate_rows'] += 1
                if instants[key][0] != values:
                    quality['conflicting_duplicates'] += 1
                # 같은 관측의 중복은 한 번만 사용합니다. 충돌 시 먼저 수집된 유효 행을 선택합니다.
                if collected >= instants[key][1]:
                    continue
            instants[key] = (values, collected)

    daily_hours = defaultdict(list)
    for (place, stamp), (values, _) in instants.items():
        daily_hours[(place, stamp.date(), stamp.hour)].append(values)
    hourly = {key: (fmean(v[0] for v in vals), fmean(v[1] for v in vals))
              for key, vals in daily_hours.items()}
    buckets = defaultdict(list)
    daily = defaultdict(dict)
    for (place, day, hour), bounds in hourly.items():
        buckets[(place, day.weekday(), hour)].append((day.isoformat(), bounds))
        daily[(place, day)][hour] = (bounds[0] + bounds[1]) / 2
    quality['unique_instants'] = len(instants)
    quality['date_place_hours'] = len(hourly)
    quality['files'] = len(used_files)
    result = []
    for place in sorted(places):
        grid = []
        for weekday in range(7):
            week = []
            for hour in range(24):
                samples = sorted(buckets[(place, weekday, hour)])
                if not samples:
                    week.append([None, 0, None, None, []])
                    continue
                low = fmean(s[1][0] for s in samples)
                high = fmean(s[1][1] for s in samples)
                week.append([round((low + high) / 2, 1), len(samples), round(low, 1),
                             round(high, 1), [s[0] for s in samples]])
            grid.append(week)
        summary = []
        for weekday in range(7):
            complete = [(d.isoformat(), fmean(hours.values())) for (p, d), hours in daily.items()
                        if p == place and d.weekday() == weekday and len(hours) == 24]
            summary.append(dict(mean=round(fmean(v for _, v in complete), 1) if complete else None,
                                n=len(complete), dates=sorted(d for d, _ in complete)))
        observed = sorted({d.isoformat() for p, d in daily if p == place})
        result.append(dict(name=place, category=places[place], grid=grid, daily=summary,
                           observed_dates=observed))
    return dict(schema_version=1, period=dict(start=start.isoformat(), end=end.isoformat(), days=days,
                as_of=as_of.isoformat(), expected_dates=expected), weekdays=WEEKDAYS, places=result,
                quality=quality, source_files=used_files,
                method='같은 날짜·장소·시간의 관측을 먼저 평균 낸 뒤, 날짜별 값을 같은 비중으로 평균합니다.',
                metric='서울시 인구 추정 최소·최대 범위의 중앙값을 평균한 값입니다. 고유 방문자 수가 아닙니다.')


def save_outputs(payload, output_root):
    target = output_root / 'site/visit-patterns.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    content = json.dumps(payload, ensure_ascii=False, separators=(',', ':'), allow_nan=False) + '\n'
    if not target.exists() or target.read_text(encoding='utf-8') != content:
        target.write_text(content, encoding='utf-8', newline='\n')
    export = output_root / 'data/analysis/방문시간_요일시간_최근30일.csv'
    export.parent.mkdir(parents=True, exist_ok=True)
    with export.open('w', encoding='utf-8-sig', newline='') as stream:
        writer = csv.writer(stream, lineterminator='\n')
        writer.writerow(['기간시작', '기간끝', '장소', '요일', '시간', '평균인구_명', '평균최소_명',
                         '평균최대_명', '관측날짜수', '대상날짜수', '누락날짜수', '관측날짜'])
        for place in payload['places']:
            for w, week in enumerate(place['grid']):
                expected = payload['period']['expected_dates'][w]
                for hour, (mean, count, low, high, dates) in enumerate(week):
                    writer.writerow([payload['period']['start'], payload['period']['end'], place['name'],
                                     WEEKDAYS[w], hour, '' if mean is None else mean,
                                     '' if low is None else low, '' if high is None else high,
                                     count, expected, expected-count, ' / '.join(dates)])
    return target


def main():
    parser = argparse.ArgumentParser(description='최근 완료된 30일의 방문 시간 비교표 만들기')
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--output', type=Path)
    parser.add_argument('--as-of', type=date.fromisoformat,
                        default=datetime.now(timezone(timedelta(hours=9))).date())
    args = parser.parse_args()
    payload = aggregate(args.source, args.as_of)
    target = save_outputs(payload, args.output or args.source)
    print(f"방문 시간 비교표: {len(payload['places'])}곳, {payload['period']['start']}~{payload['period']['end']}, 관측 날짜·장소·시간 {payload['quality']['date_place_hours']:,}개 → {target}")


if __name__ == '__main__':
    main()
