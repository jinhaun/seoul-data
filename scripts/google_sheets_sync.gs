/**
 * 서울 데이터 정기 수집 → 구글 드라이브 (구글 시트) 자동 정리   (Google Apps Script)
 *
 * GitHub 공개 저장소(jinhaun/seoul-data)의 data/ 자료를 구글 드라이브 "서울 데이터 정기 수집" 폴더에
 * 구글 시트로 정리합니다. 구글 서버에서 돌기 때문에 노트북이 꺼져 있어도 됩니다.
 *
 *   실시간 121곳/      실시간 121곳 YYYY-MM          탭 = 날짜             (1시간마다)
 *   외국인 생활인구/   외국인 단기·장기 YYYY-MM       탭 = 날짜             (매일, 서울시 공개 약 4일 지연)
 *   항공/              항공 YYYY-MM                   탭 = 날짜             (매일)
 *   행사/              행사 YYYY-MM                   탭 = 날짜 공식·웹검색  (매일)
 *   환율·숙박·기록/    환율, 숙박 현재 목록, 숙박 변경 내역, 수집 기록
 *
 * 설치 방법 (처음 한 번)
 *   1. https://script.google.com → 새 프로젝트 → 기본 코드를 지우고 이 파일 내용을 붙여넣기 → 저장
 *   2. 왼쪽 톱니바퀴(프로젝트 설정) → 시간대를 "(GMT+09:00) 서울"로
 *   3. 위쪽 함수 고르는 칸에서 setup → ▶ 실행 → 권한 검토 → 내 계정 → 허용
 *      ("확인되지 않은 앱" 경고가 나오면 "고급" → "프로젝트로 이동")
 *   그다음은 자동: 지난 자료는 10분마다 나눠서 1~2시간 안에 채우고, 이후 1시간마다 새 자료를 붙입니다.
 *   진행 상황: 왼쪽 "실행" 메뉴의 기록, 또는 드라이브 "수집 기록" 파일의 "구글 정리" 탭.
 *
 * 끄기: 왼쪽 시계 모양(트리거)에서 hourly·backfill 을 지우면 멈춥니다. 드라이브에 쌓인 자료는 그대로 남습니다.
 */

const RAW = 'https://raw.githubusercontent.com/jinhaun/seoul-data/main/';
const ROOT = '서울 데이터 정기 수집';
const TZ = 'Asia/Seoul';
const RUN_LIMIT_MS = 5 * 60 * 1000;      // 구글은 한 번에 6분까지라 5분에서 끊고 다음에 이어 함
const LODGING_KINDS = ['호텔', '외국인민박', '숙박업'];

// 날짜마다 파일이 하나씩 있는 자료 → 달마다 시트 파일 하나, 날짜마다 탭 하나
const DAILY = [
  { key: 'rt',  folder: '실시간 121곳',    start: '2026-10-16', recent: 2, file: m => '실시간 121곳 ' + m, tab: d => d,            path: d => `data/realtime/${d.slice(0, 7)}/${d}.csv` },
  { key: 'fs',  folder: '외국인 생활인구', start: '2026-01-01', recent: 8, file: m => '외국인 단기 ' + m,  tab: d => d,            path: d => `data/foreigner/단기/${d.slice(0, 7)}/${d}.csv` },
  { key: 'fl',  folder: '외국인 생활인구', start: '2026-01-01', recent: 8, file: m => '외국인 장기 ' + m,  tab: d => d,            path: d => `data/foreigner/장기/${d.slice(0, 7)}/${d}.csv` },
  { key: 'air', folder: '항공',            start: '2026-11-01', recent: 2, file: m => '항공 ' + m,         tab: d => d,            path: d => `data/flights/${d.slice(0, 7)}/${d}.csv` },
  { key: 'evo', folder: '행사',            start: '2026-10-16', recent: 2, file: m => '행사 ' + m,         tab: d => d + ' 공식',   path: d => `data/events/${d.slice(0, 7)}/${d}_공식.csv` },
  { key: 'evw', folder: '행사',            start: '2026-10-16', recent: 2, file: m => '행사 ' + m,         tab: d => d + ' 웹검색', path: d => `data/events/${d.slice(0, 7)}/${d}_웹검색.csv` },
];

// 파일 하나를 통째로 탭 하나에 (바뀌었을 때만 다시 씀)
const FLAT = [
  { key: 'fx', folder: '환율·숙박·기록', file: '환율',           tab: '환율 일별',  path: 'data/exchange/환율_일별.csv' },
  { key: 'lh', folder: '환율·숙박·기록', file: '숙박 현재 목록', tab: '호텔',       path: 'data/lodging/latest/숙박_호텔.csv' },
  { key: 'lg', folder: '환율·숙박·기록', file: '숙박 현재 목록', tab: '외국인민박', path: 'data/lodging/latest/숙박_외국인민박.csv' },
  { key: 'll', folder: '환율·숙박·기록', file: '숙박 현재 목록', tab: '숙박업',     path: 'data/lodging/latest/숙박_숙박업.csv' },
  { key: 's1', folder: '환율·숙박·기록', file: '수집 기록',      tab: '실시간',     path: 'data/status/수집기록.csv' },
  { key: 's2', folder: '환율·숙박·기록', file: '수집 기록',      tab: '매일 작업',  path: 'data/status/매일작업기록.csv' },
  { key: 's3', folder: '환율·숙박·기록', file: '수집 기록',      tab: '숙박',       path: 'data/status/숙박기록.csv' },
  { key: 's4', folder: '환율·숙박·기록', file: '수집 기록',      tab: '항공',       path: 'data/status/항공기록.csv' },
];
const LODGING_CHANGES = { folder: '환율·숙박·기록', file: '숙박 변경 내역', tab: '변경 내역', start: '2026-10-18' };

// ───────────────────────── 설치·자동 실행 ─────────────────────────

/** 처음 한 번 실행: 자동 실행 등록 + 지난 자료 채우기 시작 */
function setup() {
  ScriptApp.getProjectTriggers()
    .filter(t => ['hourly', 'backfill'].indexOf(t.getHandlerFunction()) >= 0)
    .forEach(t => ScriptApp.deleteTrigger(t));
  ScriptApp.newTrigger('hourly').timeBased().everyHours(1).create();
  ScriptApp.newTrigger('backfill').timeBased().everyMinutes(10).create();
  PropertiesService.getScriptProperties().setProperty('BACKFILL_I', '0');
  getRoot();
  backfill();
}

/** 지난 자료를 처음부터 차례로 채움 (5분씩 끊어서, 다 끝나면 스스로 멈춤) */
function backfill() {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(2000)) return;
  try {
    const props = PropertiesService.getScriptProperties();
    const jobs = backfillJobs();
    let i = Number(props.getProperty('BACKFILL_I') || 0);
    const t0 = Date.now(), log = [];
    for (; i < jobs.length && Date.now() - t0 < RUN_LIMIT_MS; i++) {
      log.push(runJob(jobs[i]));
      props.setProperty('BACKFILL_I', String(i + 1));
    }
    if (i >= jobs.length) {
      ScriptApp.getProjectTriggers().filter(t => t.getHandlerFunction() === 'backfill').forEach(t => ScriptApp.deleteTrigger(t));
      FLAT.forEach(f => log.push(runJob({ type: 'flat', spec: f })));
      log.push('지난 자료 채우기 끝');
    }
    writeRunLog('지난 자료 채우기', `${i} / ${jobs.length}`, log);
  } finally { lock.releaseLock(); }
}

/** 1시간마다: 최근 며칠 치와 통째 자료를 GitHub과 맞춤 (바뀐 것만 다시 씀) */
function hourly() {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(2000)) return;
  try {
    const t0 = Date.now(), log = [], jobs = [];
    DAILY.forEach(s => lastDays(s.recent).forEach(d => { if (d >= s.start) jobs.push({ type: 'daily', spec: s, day: d }); }));
    lastDays(2).forEach(d => LODGING_KINDS.forEach(k => jobs.push({ type: 'change', day: d, kind: k })));
    FLAT.forEach(f => jobs.push({ type: 'flat', spec: f }));
    for (const j of jobs) {
      if (Date.now() - t0 > RUN_LIMIT_MS) { log.push('시간이 모자라 다음 시간에 이어서'); break; }
      log.push(runJob(j));
    }
    writeRunLog('1시간마다', jobs.length + '개 확인', log);
  } finally { lock.releaseLock(); }
}

function backfillJobs() {
  const jobs = [], today = ymd(new Date());
  DAILY.forEach(s => daysBetween(s.start, today).forEach(d => jobs.push({ type: 'daily', spec: s, day: d })));
  daysBetween(LODGING_CHANGES.start, today).forEach(d => LODGING_KINDS.forEach(k => jobs.push({ type: 'change', day: d, kind: k })));
  return jobs;
}

function runJob(j) {
  try {
    if (j.type === 'daily') return j.spec.file(j.day.slice(0, 7)) + ' / ' + j.spec.tab(j.day) + ': ' + syncDaily(j.spec, j.day);
    if (j.type === 'flat') return j.spec.file + ' / ' + j.spec.tab + ': ' + syncFlat(j.spec);
    if (j.type === 'change') return '숙박 변경 ' + j.day + ' ' + j.kind + ': ' + syncChange(j.day, j.kind);
  } catch (e) { return '오류 - ' + e.message; }
}

// ───────────────────────── 자료 맞추기 ─────────────────────────

/** 날짜 자료 하나 → 그 달 파일의 날짜 탭 */
function syncDaily(spec, day) {
  const res = fetchCsv(spec.path(day));
  if (!res) return 'GitHub에 없음';
  const hkey = spec.key + '|' + day;
  if (sameHash(hkey, res.text)) return '변경 없음';
  const values = toValues(res.text);
  if (values.length < 1) return '빈 파일';
  const ss = getSheetFile(spec.folder, spec.file(day.slice(0, 7)));
  writeTab(ss, spec.tab(day), values);
  saveHash(hkey, res.text);
  return '저장 ' + (values.length - 1) + '줄';
}

/** 파일 하나 통째로 → 탭 하나 */
function syncFlat(spec) {
  const res = fetchCsv(spec.path);
  if (!res) return 'GitHub에 없음';
  if (sameHash(spec.key, res.text)) return '변경 없음';
  const values = toValues(res.text);
  const ss = getSheetFile(spec.folder, spec.file);
  writeTab(ss, spec.tab, values);
  saveHash(spec.key, res.text);
  return '저장 ' + (values.length - 1) + '줄';
}

/** 숙박 변경 내역: 날짜·종류 열을 붙여 한 탭에 차례로 덧붙임 (한 번 넣은 날짜·종류는 다시 안 넣음) */
function syncChange(day, kind) {
  const props = PropertiesService.getScriptProperties();
  const key = 'chg|' + day + '|' + kind;
  if (props.getProperty(key)) return '이미 넣음';
  const res = fetchCsv(`data/lodging/changes/${day.slice(0, 7)}/${day}_${kind}.csv`);
  if (!res) return '없음';
  const values = toValues(res.text);
  if (!values.length) return '빈 파일';
  const ss = getSheetFile(LODGING_CHANGES.folder, LODGING_CHANGES.file);
  let sh = ss.getSheetByName(LODGING_CHANGES.tab);
  if (!sh) sh = ss.insertSheet(LODGING_CHANGES.tab);
  if (sh.getLastRow() === 0) { sh.appendRow(['날짜', '종류'].concat(values[0])); styleHeader(sh, values[0].length + 2); }
  const rows = values.slice(1).map(r => [day, kind].concat(r));
  if (rows.length) sh.getRange(sh.getLastRow() + 1, 1, rows.length, rows[0].length).setValues(rows);
  removeDefaultSheet(ss);
  props.setProperty(key, '1');
  return '추가 ' + rows.length + '줄';
}

// ───────────────────────── 도우미 ─────────────────────────

/** GitHub 원본 CSV 받기. 없으면 null */
function fetchCsv(path) {
  const url = RAW + path.split('/').map(encodeURIComponent).join('/');
  const res = UrlFetchApp.fetch(url, { muteHttpExceptions: true });
  const code = res.getResponseCode();
  if (code === 404) return null;
  if (code !== 200) throw new Error('GitHub 응답 ' + code);
  return { text: res.getContentText('UTF-8').replace(/^﻿/, '') };
}

/** CSV 글자 → 시트에 넣을 2차원 배열 (모든 줄의 칸 수를 맞춤) */
function toValues(text) {
  const rows = Utilities.parseCsv(text).filter(r => r.length > 1 || (r.length === 1 && r[0] !== ''));
  if (!rows.length) return [];
  const w = Math.max.apply(null, rows.map(r => r.length));
  return rows.map((r, i) => {
    const out = r.map(v => (i === 0 ? v : toCell(v)));
    while (out.length < w) out.push('');
    return out;
  });
}

/** 숫자처럼 생긴 값은 숫자로. 단 0으로 시작하는 번호(0000123 등)와 아주 긴 번호는 글자 그대로 */
function toCell(v) {
  return /^-?(0|[1-9]\d{0,14})(\.\d+)?$/.test(v) ? Number(v) : v;
}

function writeTab(ss, name, values) {
  let sh = ss.getSheetByName(name);
  if (!sh) sh = ss.insertSheet(name, sortedIndex(ss, name));
  sh.clearContents();
  if (values.length && values[0].length) {
    sh.getRange(1, 1, values.length, values[0].length).setValues(values);
    styleHeader(sh, values[0].length);
  }
  removeDefaultSheet(ss);
}

function styleHeader(sh, cols) {
  sh.setFrozenRows(1);
  sh.getRange(1, 1, 1, cols).setFontWeight('bold').setBackground('#dff2ef');
}

/** 탭을 이름 순서(날짜 순)로 놓음 */
function sortedIndex(ss, name) {
  return ss.getSheets().map(s => s.getName()).filter(n => !isDefaultName(n) && n.localeCompare(name) < 0).length;
}

function isDefaultName(n) { return /^(Sheet|시트)\d+$/.test(n); }

/** 새 파일에 자동으로 생기는 빈 "시트1" 정리 */
function removeDefaultSheet(ss) {
  ss.getSheets().filter(s => isDefaultName(s.getName()) && s.getLastRow() === 0)
    .forEach(s => { if (ss.getSheets().length > 1) ss.deleteSheet(s); });
}

function getRoot() {
  const it = DriveApp.getFoldersByName(ROOT);
  return it.hasNext() ? it.next() : DriveApp.createFolder(ROOT);
}

function getFolder(name) {
  const root = getRoot(), it = root.getFoldersByName(name);
  return it.hasNext() ? it.next() : root.createFolder(name);
}

/** 폴더 안의 시트 파일 (없으면 만듦). 같은 실행 안에서는 다시 찾지 않음 */
const FILE_CACHE = {};
function getSheetFile(folderName, fileName) {
  const k = folderName + '/' + fileName;
  if (FILE_CACHE[k]) return FILE_CACHE[k];
  const folder = getFolder(folderName), it = folder.getFilesByName(fileName);
  let ss;
  if (it.hasNext()) {
    ss = SpreadsheetApp.open(it.next());
  } else {
    ss = SpreadsheetApp.create(fileName);
    DriveApp.getFileById(ss.getId()).moveTo(folder);
  }
  FILE_CACHE[k] = ss;
  return ss;
}

/** 내용이 지난번과 같은지 (요약값으로 비교) */
function digest(text) {
  return Utilities.base64Encode(Utilities.computeDigest(Utilities.DigestAlgorithm.MD5, text, Utilities.Charset.UTF_8));
}
function sameHash(key, text) { return PropertiesService.getScriptProperties().getProperty('h|' + key) === digest(text); }
function saveHash(key, text) { PropertiesService.getScriptProperties().setProperty('h|' + key, digest(text)); }

/** 실행 기록을 "수집 기록" 파일의 "구글 정리" 탭에 한 줄씩 (최근 300줄만 유지) */
function writeRunLog(kind, summary, log) {
  console.log(kind + ' ' + summary + '\n' + log.join('\n'));
  try {
    const ss = getSheetFile('환율·숙박·기록', '수집 기록');
    let sh = ss.getSheetByName('구글 정리');
    if (!sh) { sh = ss.insertSheet('구글 정리', 0); sh.appendRow(['실행 시각', '종류', '요약', '저장·오류']); styleHeader(sh, 4); }
    const changed = log.filter(l => /저장|추가|오류/.test(l));
    sh.appendRow([Utilities.formatDate(new Date(), TZ, 'yyyy-MM-dd HH:mm'), kind, summary, changed.slice(0, 20).join(' | ') || '바뀐 것 없음']);
    const extra = sh.getLastRow() - 301;
    if (extra > 0) sh.deleteRows(2, extra);
    removeDefaultSheet(ss);
  } catch (e) { console.log('실행 기록 실패: ' + e.message); }
}

// ───────────────────────── 날짜 ─────────────────────────

function ymd(date) { return Utilities.formatDate(date, TZ, 'yyyy-MM-dd'); }

/** 오늘 포함 최근 n일 (오래된 날부터) */
function lastDays(n) {
  const out = [];
  for (let i = n - 1; i >= 0; i--) out.push(ymd(new Date(Date.now() - i * 86400000)));
  return out;
}

/** 시작일부터 끝일까지 (끝일 포함) */
function daysBetween(start, end) {
  const out = [];
  let t = new Date(start + 'T12:00:00+09:00').getTime();
  const last = new Date(end + 'T12:00:00+09:00').getTime();
  for (; t <= last; t += 86400000) out.push(ymd(new Date(t)));
  return out;
}
