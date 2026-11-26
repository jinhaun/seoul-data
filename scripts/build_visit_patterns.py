"""실제 관측을 날짜별 같은 비중으로 집계하고 날짜별 조회 자료를 만듭니다."""
import argparse
import calendar
import csv
import json
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from statistics import fmean

WEEKDAYS = ['월', '화', '수', '목', '금', '토', '일']
PRESETS = [(1, '최근 1개월'), (3, '최근 3개월'), (6, '최근 6개월'), (12, '최근 1년')]


def read_csv(path):
    with path.open(encoding='utf-8-sig', newline='') as handle:
        yield from csv.DictReader(handle)


def months_before(day, months):
    index = day.year*12 + day.month-1-months
    year, month0 = divmod(index, 12)
    month = month0+1
    return date(year, month, min(day.day, calendar.monthrange(year, month)[1]))


def load_observations(source_root, through):
    """전체 누적 자료를 한 번 읽습니다. 인증값·외부 통신은 사용하지 않습니다."""
    places = {}
    meta = source_root/'data/meta/장소_121곳.csv'
    if meta.exists():
        places = {r['장소']: r.get('분류', '') for r in read_csv(meta) if r.get('장소')}
    instants, files = {}, []
    counts = defaultdict(lambda: dict(source_rows=0, invalid_rows=0, duplicate_rows=0, conflicting_duplicates=0))
    for path in sorted((source_root/'data/realtime').glob('*/*.csv')):
        try:
            file_day = date.fromisoformat(path.stem)
        except ValueError:
            continue
        if file_day>through:
            continue
        files.append((file_day, path.relative_to(source_root).as_posix()))
        for row in read_csv(path):
            quality = counts[file_day]
            quality['source_rows'] += 1
            try:
                stamp = datetime.strptime(row['인구기준시각'], '%Y-%m-%d %H:%M')
                if stamp.date()>through:
                    continue
                place = row['장소'].strip()
                low, high = int(row['인구_최소']), int(row['인구_최대'])
                if not place or low<0 or high<low:
                    raise ValueError('잘못된 인구 범위')
            except (ValueError, KeyError, TypeError):
                quality['invalid_rows'] += 1
                continue
            places.setdefault(place, '')
            key = (place, stamp)
            collected = row.get('수집시각', '')
            record = (low, high, collected, row.get('혼잡도', '').strip())
            if key in instants:
                quality['duplicate_rows'] += 1
                if instants[key][:2]!=record[:2]:
                    quality['conflicting_duplicates'] += 1
                # 시각이 비어 있는 행보다 수집 시각을 아는 행을 우선합니다.
                if (collected or '9999') >= (instants[key][2] or '9999'):
                    continue
            instants[key] = record
    return dict(places=places, instants=instants, counts=counts, files=files,
                first=min((s.date() for _, s in instants), default=None))


def aggregate(source_root, as_of, days=30, months=None, loaded=None):
    loaded = loaded or load_observations(source_root, as_of)
    end = as_of-timedelta(days=1)
    start = months_before(as_of, months) if months else as_of-timedelta(days=days)
    days = (end-start).days+1
    dates = [start+timedelta(days=i) for i in range(days)]
    expected = [sum(d.weekday()==w for d in dates) for w in range(7)]
    first = loaded['first']
    possible = [sum(d.weekday()==w and (first is not None and d>=first) for d in dates) for w in range(7)]
    quality = {k: sum(v[k] for d, v in loaded['counts'].items() if start<=d<=end)
               for k in ['source_rows', 'invalid_rows', 'duplicate_rows', 'conflicting_duplicates']}
    used_files = [p for d, p in loaded['files'] if start<=d<=end]
    daily_hours = defaultdict(list)
    for (place, stamp), record in loaded['instants'].items():
        if start<=stamp.date()<=end:
            daily_hours[(place, stamp.date(), stamp.hour)].append(record[:2])
    hourly = {key: (fmean(v[0] for v in vals), fmean(v[1] for v in vals)) for key, vals in daily_hours.items()}
    buckets, daily = defaultdict(list), defaultdict(dict)
    for (place, day, hour), bounds in hourly.items():
        buckets[(place, day.weekday(), hour)].append((day.isoformat(), bounds))
        daily[(place, day)][hour] = fmean(bounds)
    quality.update(unique_instants=sum(len(v) for v in daily_hours.values()), date_place_hours=len(hourly), files=len(used_files))
    result = []
    for place in sorted(loaded['places']):
        grid = []
        for weekday in range(7):
            week = []
            for hour in range(24):
                samples = sorted(buckets[(place, weekday, hour)])
                if not samples:
                    week.append([None, 0, None, None, []])
                    continue
                low, high = (fmean(s[1][i] for s in samples) for i in (0, 1))
                week.append([round((low+high)/2, 1), len(samples), round(low, 1), round(high, 1), [s[0] for s in samples]])
            grid.append(week)
        summary = []
        for weekday in range(7):
            complete = [(d.isoformat(), fmean(hours.values())) for (p, d), hours in daily.items()
                        if p==place and d.weekday()==weekday and len(hours)==24]
            summary.append(dict(mean=round(fmean(v for _, v in complete), 1) if complete else None,
                                n=len(complete), dates=sorted(d for d, _ in complete)))
        result.append(dict(name=place, category=loaded['places'][place], grid=grid, daily=summary,
                           observed_dates=sorted({d.isoformat() for p, d in daily if p==place})))
    available = sorted({d.isoformat() for _, d, _ in hourly})
    return dict(schema_version=2, period=dict(start=start.isoformat(), end=end.isoformat(), days=days, months=months,
                as_of=as_of.isoformat(), expected_dates=expected, possible_dates=possible,
                collection_start=first.isoformat() if first else None,
                available_start=available[0] if available else None, available_end=available[-1] if available else None,
                available_days=len(available), before_collection_days=sum(expected)-sum(possible)),
                weekdays=WEEKDAYS, places=result, quality=quality, source_files=used_files,
                method='같은 날짜·장소·시간의 관측을 먼저 평균 낸 뒤, 날짜별 값을 같은 비중으로 평균합니다.',
                metric='서울시 인구 추정 최소·최대 범위의 중앙값을 평균한 값입니다. 고유 방문자 수가 아닙니다.')


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    content = json.dumps(payload, ensure_ascii=False, separators=(',', ':'), allow_nan=False)+'\n'
    if not path.exists() or path.read_text(encoding='utf-8')!=content:
        path.write_text(content, encoding='utf-8', newline='\n')


def save_outputs(payload, output_root, stem=None):
    target = output_root/('site/patterns/'+stem+'.json' if stem else 'site/visit-patterns.json')
    write_json(target, payload)
    export = output_root/'data/analysis'/(f'방문시간_요일시간_{stem}개월.csv' if stem else '방문시간_요일시간_최근30일.csv')
    export.parent.mkdir(parents=True, exist_ok=True)
    with export.open('w', encoding='utf-8-sig', newline='') as stream:
        writer = csv.writer(stream, lineterminator='\n')
        writer.writerow(['기간시작', '기간끝', '장소', '요일', '시간', '평균인구_명', '평균최소_명',
                         '평균최대_명', '관측날짜수', '대상날짜수', '누락날짜수', '관측날짜', '수집전날짜수', '수집후누락날짜수'])
        for place in payload['places']:
            for w, week in enumerate(place['grid']):
                expected = payload['period']['expected_dates'][w]
                possible = payload['period']['possible_dates'][w]
                for hour, (mean, count, low, high, dates) in enumerate(week):
                    writer.writerow([payload['period']['start'], payload['period']['end'], place['name'], WEEKDAYS[w], hour,
                                     '' if mean is None else mean, '' if low is None else low, '' if high is None else high,
                                     count, expected, expected-count, ' / '.join(dates), expected-possible, possible-count])
    return target


def build_history(loaded, output_root, as_of):
    days = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    for (place, stamp), (low, high, _, level) in sorted(loaded['instants'].items()):
        days[stamp.date().isoformat()][place][stamp.hour].append([stamp.strftime('%H:%M'), low, high, level])
    dates = []
    for day, places in sorted(days.items()):
        result = []
        for place, hours in sorted(places.items()):
            grid = [None]*24
            for hour, observations in hours.items():
                low, high = (fmean(v[i] for v in observations) for i in (1, 2))
                grid[hour] = [round((low+high)/2, 1), round(low, 1), round(high, 1), observations]
            result.append(dict(name=place, hours=grid))
        write_json(output_root/f'site/history/{day[:7]}/{day}.json', dict(date=day, places=result))
        dates.append(day)
    manifest = dict(schema_version=2, as_of=as_of.isoformat(), dates=dates,
                    first_date=dates[0] if dates else None, last_date=dates[-1] if dates else None,
                    presets=[dict(months=m, label=label, path=f'site/patterns/{m}.json',
                                  download=f'data/analysis/방문시간_요일시간_{m}개월.csv') for m, label in PRESETS])
    write_json(output_root/'site/visit-manifest.json', manifest)
    return manifest


def main():
    parser = argparse.ArgumentParser(description='기간별 방문 시간 평균과 날짜별 조회 자료 만들기')
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--output', type=Path)
    parser.add_argument('--as-of', type=date.fromisoformat, default=datetime.now(timezone(timedelta(hours=9))).date())
    args = parser.parse_args()
    output = args.output or args.source
    loaded = load_observations(args.source, args.as_of)
    save_outputs(aggregate(args.source, args.as_of, loaded=loaded), output)
    for months, _ in PRESETS:
        save_outputs(aggregate(args.source, args.as_of, months=months, loaded=loaded), output, str(months))
    manifest = build_history(loaded, output, args.as_of)
    print(f"방문 시간 비교표: {len(loaded['places'])}곳, 1·3·6·12개월, 날짜별 기록 {len(manifest['dates'])}일")


if __name__=='__main__':
    main()
