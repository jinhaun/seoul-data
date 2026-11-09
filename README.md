# seoul-data
서울 실시간 유동인구·외국인 데이터 자동 수집

👉 **사이트: https://jinhaun.github.io/seoul-data/**
📘 **작업 설명서 (구조·노트북 설정·문제 해결): [AGENTS.md](AGENTS.md)**
🚀 **새 노트북에서 Claude·Codex로 시작하기: [시작_프롬프트.md](시작_프롬프트.md)**

GitHub Actions가 컴퓨터 없이 알아서 모읍니다. 한 번 실행되면 5시간 반 동안 켜진 채 10분마다 확인하고, 끝날 때 다음 실행을 스스로 띄우는 "이어달리기" 방식입니다.

| 언제 | 무엇 | 저장 위치 |
|---|---|---|
| 1시간마다 | 서울 실시간 도시데이터 121곳 (혼잡도·인구·연령·날씨·교통) | `data/realtime/YYYY-MM/YYYY-MM-DD.csv` |
| 1시간마다 | 원본 JSON (압축) | [Releases](https://github.com/jinhaun/seoul-data/releases) `raw-YYYY-MM` |
| 매일 9시 이후 첫 수집 | 서울시 문화행사·공연장 일정·교통통제 | `data/events/YYYY-MM/YYYY-MM-DD_공식.csv` |
| 〃 | 숙박업소 (호텔·외국인민박·숙박업) 전체 + 바뀐 곳 | `data/lodging/latest/`, `data/lodging/changes/` |
| 〃 | 외국인 생활인구 (자치구 × 시간 × 국적, 단기·장기, 약 4일 지연) | `data/foreigner/단기·장기/YYYY-MM/YYYY-MM-DD.csv` |
| 〃 | 원화 환율 (달러·100엔·위안·바트·루피·유로) | `data/exchange/환율_일별.csv` |
| 〃 | 김포·인천 여객기 운항정보 (어제 최종 + 오늘) | `data/flights/YYYY-MM/YYYY-MM-DD.csv` |
| 수집할 때마다 | 수집 성공/실패 기록 | `data/status/` |

- 2026-10-16 ~ 12월 초 자료에는 노트북에서 30분(초기 5분)마다 모은 것이 함께 들어 있습니다. 노트북에서 쓰던 프로그램은 `laptop/` 폴더에 있습니다.
- 손으로 실행: **Actions** 탭 → 실시간 수집 → **Run workflow**
- 필요한 설정: Settings → Secrets → `SEOUL_API_KEY` (서울 열린데이터광장), `DATA_GO_KR_KEY` (공공데이터포털)

## 출처
- 서울 열린데이터광장 (공공누리 제1유형: 출처표시) — 실시간 도시데이터, 외국인 생활인구, 문화행사 정보, 교통통제 정보, 숙박업 인허가 정보
- 서울시설공단 공연장 일정
- 공공데이터포털 — 한국공항공사 실시간 항공기 운항정보, 인천국제공항공사 여객기 운항 현황
- 환율: European Central Bank 기준환율 ([Frankfurter API](https://frankfurter.dev))
- 글꼴: 나눔스퀘어 네오 (네이버, SIL 오픈 폰트 라이선스)
