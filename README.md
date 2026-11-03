# seoul-data
서울 실시간 유동인구·외국인 데이터 자동 수집

👉 **사이트: https://jinhaun.github.io/seoul-data/**

GitHub Actions가 컴퓨터 없이 알아서 모읍니다.

| 언제 | 무엇 | 저장 위치 |
|---|---|---|
| 매시 33분 | 서울 실시간 도시데이터 121곳 (혼잡도·인구·연령·날씨·교통) | `data/realtime/YYYY-MM/YYYY-MM-DD.csv` |
| 매시 33분 | 원본 JSON (압축) | [Releases](https://github.com/jinhaun/seoul-data/releases) `raw-YYYY-MM` |
| 매일 09:05 | 서울시 문화행사·공연장 일정·교통통제 | `data/events/YYYY-MM/YYYY-MM-DD_공식.csv` |
| 매일 09:05 | 숙박업소 (호텔·외국인민박·숙박업) 전체 + 바뀐 곳 | `data/lodging/latest/`, `data/lodging/changes/` |
| 매일 09:05 | 외국인 생활인구 (자치구 × 시간 × 국적, 단기·장기, 약 4일 지연) | `data/foreigner/단기·장기/YYYY-MM/YYYY-MM-DD.csv` |
| 매일 09:05 | 원화 환율 (달러·100엔·위안·바트·루피·유로) | `data/exchange/환율_일별.csv` |
| 실행마다 | 수집 성공/실패 기록 | `data/status/` |

- 2026-10-16 ~ 12월 초 자료는 노트북에서 30분(초기 5분)마다 모은 것을 옮겨 왔습니다. 이후는 1시간마다입니다.
- 손으로 실행: **Actions** 탭 → 워크플로 선택 → **Run workflow**
- 필요한 설정: Settings → Secrets → `SEOUL_API_KEY` (서울 열린데이터광장 인증키)

## 출처
- 서울 열린데이터광장 (공공누리 제1유형: 출처표시) — 실시간 도시데이터, 외국인 생활인구, 문화행사 정보, 교통통제 정보, 숙박업 인허가 정보
- 서울시설공단 공연장 일정
- 환율: European Central Bank 기준환율 ([Frankfurter API](https://frankfurter.dev))
