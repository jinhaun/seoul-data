# 서울 실시간 유동인구 엑셀 만들기
#   data\날짜_요일\HHmm.json.gz (collect.ps1 이 30분마다 저장한 citydata 응답)에서
#   장소별 실시간 인구(LIVE_PPLTN_STTS)만 뽑아 실시간_유동인구\서울_실시간_유동인구.xlsx 로 정리합니다.
#   시트: 출처 / 원자료 / 장소별_요약 / 시간대별_평균
#   다시 만들려면 이 파일만 실행하면 됩니다 (새로 쌓인 데이터까지 모두 반영).

$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir = Join-Path $Root 'data'
$OutDir  = Join-Path $Root '실시간_유동인구'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$Font = '맑은 고딕'

# ---------- 1) gz 파일에서 실시간 인구만 빠르게 추출 ----------
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Text.RegularExpressions;
public static class PpltnExtract {
    static readonly Regex Rx = new Regex(
        "\"LIVE_PPLTN_STTS\":\\[\\{\"AREA_NM\":\"(?<nm>[^\"]*)\",\"AREA_CD\":\"(?<cd>[^\"]*)\",\"AREA_CONGEST_LVL\":\"(?<lvl>[^\"]*)\",\"AREA_CONGEST_MSG\":\"[^\"]*\"," +
        "\"AREA_PPLTN_MIN\":\"(?<min>[^\"]*)\",\"AREA_PPLTN_MAX\":\"(?<max>[^\"]*)\",\"MALE_PPLTN_RATE\":\"(?<m>[^\"]*)\",\"FEMALE_PPLTN_RATE\":\"(?<f>[^\"]*)\"," +
        "\"PPLTN_RATE_0\":\"(?<a0>[^\"]*)\",\"PPLTN_RATE_10\":\"(?<a10>[^\"]*)\",\"PPLTN_RATE_20\":\"(?<a20>[^\"]*)\",\"PPLTN_RATE_30\":\"(?<a30>[^\"]*)\"," +
        "\"PPLTN_RATE_40\":\"(?<a40>[^\"]*)\",\"PPLTN_RATE_50\":\"(?<a50>[^\"]*)\",\"PPLTN_RATE_60\":\"(?<a60>[^\"]*)\",\"PPLTN_RATE_70\":\"(?<a70>[^\"]*)\"," +
        "\"RESNT_PPLTN_RATE\":\"(?<r>[^\"]*)\",\"NON_RESNT_PPLTN_RATE\":\"(?<nr>[^\"]*)\",\"REPLACE_YN\":\"(?<rep>[^\"]*)\",\"PPLTN_TIME\":\"(?<t>[^\"]*)\"",
        RegexOptions.Compiled);
    public static readonly string[] Keys = { "t","cd","nm","lvl","min","max","m","f","a0","a10","a20","a30","a40","a50","a60","a70","r","nr","rep" };
    // 반환: 각 행 = Keys 순서 값 + 원본파일 + 수집시각
    public static List<string[]> Run(string[] files, out int dup, out int bad) {
        var rows = new List<string[]>(); var seen = new HashSet<string>(); dup = 0; bad = 0;
        var rxCol = new Regex("\"collected_at\":\"([^\"]*)\"");
        foreach (var f in files) {
            string text;
            try {
                using (var fs = File.OpenRead(f)) using (var gz = new GZipStream(fs, CompressionMode.Decompress))
                using (var sr = new StreamReader(gz, Encoding.UTF8)) text = sr.ReadToEnd();
            } catch { bad++; continue; }
            var cm = rxCol.Match(text); string col = cm.Success ? cm.Groups[1].Value : "";
            string rel = Path.GetFileName(Path.GetDirectoryName(f)) + "/" + Path.GetFileName(f);
            foreach (Match m in Rx.Matches(text)) {
                string key = m.Groups["cd"].Value + "|" + m.Groups["t"].Value;
                if (!seen.Add(key)) { dup++; continue; }
                var row = new string[Keys.Length + 2];
                for (int i = 0; i < Keys.Length; i++) row[i] = m.Groups[Keys[i]].Value;
                row[Keys.Length] = rel; row[Keys.Length + 1] = col;
                rows.Add(row);
            }
        }
        rows.Sort((a, b) => { int c = string.CompareOrdinal(a[0], b[0]); return c != 0 ? c : string.CompareOrdinal(a[2], b[2]); });
        return rows;
    }
}
'@

$files = @(Get-ChildItem $DataDir -Recurse -File -Filter '*.json.gz' | Where-Object { $_.Name -match '^\d{4}(_\d{4})?\.json\.gz$' } | Sort-Object FullName | ForEach-Object { $_.FullName })
"스냅샷 파일 $($files.Count)개 읽는 중..."
$dup = 0; $bad = 0
$rows = [PpltnExtract]::Run($files, [ref]$dup, [ref]$bad)
"추출 $($rows.Count)행 (중복 제외 $dup, 읽기 실패 파일 $bad)"
if ($rows.Count -eq 0) { throw '추출된 데이터가 없습니다.' }

# ---------- 2) 장소 분류 (관광특구/발달상권/인구밀집지역/공원/고궁·문화유산) ----------
$cat = @{}
try {
    $wc = New-Object Net.WebClient; $wc.Headers.Add('Referer', 'https://data.seoul.go.kr/SeoulRtd/list')
    $j = [Text.Encoding]::UTF8.GetString($wc.DownloadData('https://data.seoul.go.kr/SeoulRtd/api/hotspot-category?page=1&category=%EC%A0%84%EC%B2%B4%EB%B3%B4%EA%B8%B0&count=300')) | ConvertFrom-Json
    foreach ($r in $j.row) { $cat[$r.area_nm] = $r.category }
} catch { "WARN 분류 목록을 못 받음: $($_.Exception.Message)" }

# ---------- 3) 엑셀 배열 만들기 ----------
$ko = [Globalization.CultureInfo]::GetCultureInfo('ko-KR')
$hdr = @('기준시각','날짜','요일','평일주말','시','장소코드','장소명','분류','혼잡도','인구_최소(명)','인구_최대(명)','인구_중간값(명)',
         '남성(%)','여성(%)','0~9세(%)','10대(%)','20대(%)','30대(%)','40대(%)','50대(%)','60대(%)','70대이상(%)',
         '상주인구(%)','비상주인구(%)','대체데이터여부','원본파일','수집시각')
$hdr += '이상치의심'
$n = $rows.Count; $nc = $hdr.Count

# 이상치: 그 시각 전체 장소 평균 인구가 앞뒤 3개 시각의 중앙값보다 1.6배 이상 크거나 0.6배 이하이면
#   API 쪽 일시 오류로 보고 Y (예: 2026-10-21 16:00 에 모든 장소가 2배로 찍혔다가 16:30에 되돌아옴)
$tot = @{}; $cntT = @{}
foreach ($r in $rows) { $mid = ([double]$r[4] + [double]$r[5]) / 2; $tot[$r[0]] += $mid; $cntT[$r[0]] += 1 }
$times = @($tot.Keys | Sort-Object)
$avgT = @{}; foreach ($t in $times) { $avgT[$t] = $tot[$t] / $cntT[$t] }
$outlier = @{}
for ($i = 0; $i -lt $times.Count; $i++) {
    $nb = @(); for ($j = [Math]::Max(0, $i - 3); $j -le [Math]::Min($times.Count - 1, $i + 3); $j++) { if ($j -ne $i) { $nb += $avgT[$times[$j]] } }
    $nb = @($nb | Sort-Object); $med = $nb[[int][Math]::Floor($nb.Count / 2)]
    $ratio = $avgT[$times[$i]] / $med
    if ($ratio -ge 1.6 -or $ratio -le 0.6) { $outlier[$times[$i]] = $ratio }
}
"이상치 의심 시각 $($outlier.Count)개: " + (($outlier.Keys | Sort-Object | ForEach-Object { '{0} (x{1:N2})' -f $_, $outlier[$_] }) -join ', ')
$arr = New-Object 'object[,]' ($n + 1), $nc
for ($c = 0; $c -lt $nc; $c++) { $arr[0, $c] = $hdr[$c] }
$num = { param($s) $v = 0.0; if ([double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { $v } else { $null } }
$places = [ordered]@{}; $peak = @{}
for ($i = 0; $i -lt $n; $i++) {
    $r = $rows[$i]; $k = $i + 1; $row = $k + 1
    $dt = [datetime]::ParseExact($r[0], 'yyyy-MM-dd HH:mm', $null)
    $dow = $dt.DayOfWeek
    $arr[$k, 0] = $dt.ToOADate()
    $arr[$k, 1] = $dt.Date.ToOADate()
    $arr[$k, 2] = $dt.ToString('ddd', $ko)
    $arr[$k, 3] = $(if ($dow -eq 'Saturday' -or $dow -eq 'Sunday') { '주말' } else { '평일' })
    $arr[$k, 4] = $dt.Hour
    $arr[$k, 5] = $r[1]; $arr[$k, 6] = $r[2]
    $arr[$k, 7] = $(if ($cat.ContainsKey($r[2])) { $cat[$r[2]] } else { '' })
    $arr[$k, 8] = $r[3]
    $arr[$k, 9] = & $num $r[4]; $arr[$k, 10] = & $num $r[5]
    $arr[$k, 11] = "=(J$row+K$row)/2"
    for ($c = 6; $c -le 17; $c++) { $arr[$k, ($c + 6)] = & $num $r[$c] }   # 남성%~비상주%
    $arr[$k, 24] = $r[18]; $arr[$k, 25] = $r[19]; $arr[$k, 26] = $r[20]
    $isOut = $outlier.ContainsKey($r[0])
    $arr[$k, 27] = $(if ($isOut) { 'Y' } else { 'N' })
    if (-not $places.Contains($r[1])) { $places[$r[1]] = $r[2] }
    $mid = ((& $num $r[4]) + (& $num $r[5])) / 2
    if (-not $isOut -and (-not $peak.ContainsKey($r[1]) -or $mid -gt $peak[$r[1]][0])) { $peak[$r[1]] = @($mid, $r[0]) }
}
$last = $n + 1
$first = [datetime]::ParseExact($rows[0][0], 'yyyy-MM-dd HH:mm', $null)
$lastT = [datetime]::ParseExact($rows[$n - 1][0], 'yyyy-MM-dd HH:mm', $null)
$codes = @($places.Keys | Sort-Object { $places[$_] })
"장소 $($codes.Count)곳, 기간 $first ~ $lastT"

function Style-Header($ws, $cols) {
    $h = $ws.Range($ws.Cells(1, 1), $ws.Cells(1, $cols))
    $h.Font.Bold = $true; $h.Font.Color = 0xFFFFFF; $h.Interior.Color = 0x6B3A1F   # 남색(BGR)
    $h.WrapText = $true; $h.VerticalAlignment = -4108
    $ws.Activate(); $ws.Application.ActiveWindow.SplitRow = 1; $ws.Application.ActiveWindow.FreezePanes = $true
}

function Write-Block($ws, $a, $rows, $cols) {
    try { $ws.Range($ws.Cells(1, 1), $ws.Cells($rows, $cols)).Formula = $a }
    catch {
        for ($i = 0; $i -lt $rows; $i++) { for ($c = 0; $c -lt $cols; $c++) {
            try { $ws.Cells($i + 1, $c + 1).Formula = $a[$i, $c] } catch { throw "$($ws.Name) 칸 ($($i + 1),$($c + 1)) 실패: [$($a[$i, $c])]" }
        } }
    }
}

# ---------- 4) 엑셀 쓰기 ----------
$xf = Join-Path $OutDir '서울_실시간_유동인구.xlsx'
$xl = New-Object -ComObject Excel.Application
$xl.Visible = $false; $xl.DisplayAlerts = $false; $xl.ScreenUpdating = $false
try {
    $wb = $xl.Workbooks.Add()
    $xl.Calculation = -4135   # 수동 계산 (쓰는 동안 재계산 방지)
    while ($wb.Worksheets.Count -lt 4) { $wb.Worksheets.Add([Type]::Missing, $wb.Worksheets.Item($wb.Worksheets.Count)) | Out-Null }
    $wsSrc = $wb.Worksheets.Item(1); $wsSrc.Name = '출처'
    $wsRaw = $wb.Worksheets.Item(2); $wsRaw.Name = '원자료'
    $wsSum = $wb.Worksheets.Item(3); $wsSum.Name = '장소별_요약'
    $wsHr  = $wb.Worksheets.Item(4); $wsHr.Name  = '시간대별_평균'
    foreach ($w in @($wsSrc, $wsRaw, $wsSum, $wsHr)) { $w.Cells.Font.Name = $Font; $w.Cells.Font.Size = 10 }

    # --- 원자료 ---
    $wsRaw.Range($wsRaw.Cells(1, 1), $wsRaw.Cells($last, $nc)).Value2 = $arr
    $wsRaw.Range("A2:A$last").NumberFormat = 'yyyy-mm-dd hh:mm'
    $wsRaw.Range("B2:B$last").NumberFormat = 'yyyy-mm-dd'
    $wsRaw.Range("J2:L$last").NumberFormat = '#,##0'
    $wsRaw.Range("M2:X$last").NumberFormat = '0.0'
    Style-Header $wsRaw $nc
    $wsRaw.Range("A1:AB$last").AutoFilter() | Out-Null
    $wsRaw.Columns.Item('A:AB').ColumnWidth = 10
    $wsRaw.Columns.Item('A').ColumnWidth = 16; $wsRaw.Columns.Item('G').ColumnWidth = 26; $wsRaw.Columns.Item('Z:AA').ColumnWidth = 22
    $wsRaw.Rows.Item(1).RowHeight = 30

    # --- 장소별_요약 (모두 원자료를 참조하는 수식) ---
    $rg = { param($col) "원자료!`$$col`$2:`$$col`$$last" }
    $RngCode = & $rg 'F'; $RngMid = & $rg 'L'; $RngWk = & $rg 'D'; $RngLvl = & $rg 'I'
    $OK = "$(& $rg 'AB'),`"N`""   # 이상치 제외 조건
    $sh = @('장소코드','장소명','분류','관측횟수','평균인구(명)','평일평균(명)','주말평균(명)','주말÷평일(배)','최고인구(명)','최고 기록 시각','최저인구(명)','붐빔 비율','평균인구 순위')
    $m = $codes.Count; $sa = New-Object 'object[,]' ($m + 1), $sh.Count
    for ($c = 0; $c -lt $sh.Count; $c++) { $sa[0, $c] = $sh[$c] }
    for ($i = 0; $i -lt $m; $i++) {
        $cd = $codes[$i]; $r = $i + 2; $nm = $places[$cd]
        $sa[($i + 1), (0)] = $cd; $sa[($i + 1), (1)] = $nm
        $sa[($i + 1), (2)] = $(if ($cat.ContainsKey($nm)) { $cat[$nm] } else { '' })
        $sa[($i + 1), (3)] = "=COUNTIFS($RngCode,A$r,$OK)"
        $sa[($i + 1), (4)] = "=IFERROR(AVERAGEIFS($RngMid,$RngCode,A$r,$OK),`"`")"
        $sa[($i + 1), (5)] = "=IFERROR(AVERAGEIFS($RngMid,$RngCode,A$r,$RngWk,`"평일`",$OK),`"`")"
        $sa[($i + 1), (6)] = "=IFERROR(AVERAGEIFS($RngMid,$RngCode,A$r,$RngWk,`"주말`",$OK),`"`")"
        $sa[($i + 1), (7)] = "=IFERROR(G$r/F$r,`"`")"
        $sa[($i + 1), (8)] = "=MAXIFS($RngMid,$RngCode,A$r,$OK)"
        $sa[($i + 1), (9)] = [datetime]::ParseExact($peak[$cd][1], 'yyyy-MM-dd HH:mm', $null).ToOADate()
        $sa[($i + 1), (10)] = "=MINIFS($RngMid,$RngCode,A$r,$OK)"
        $sa[($i + 1), (11)] = "=IFERROR(COUNTIFS($RngCode,A$r,$RngLvl,`"붐빔`",$OK)/D$r,0)"
        $sa[($i + 1), (12)] = "=RANK(E$r,`$E`$2:`$E`$$($m + 1),0)"
    }
    Write-Block $wsSum $sa ($m + 1) $sh.Count
    $e = $m + 1
    $wsSum.Range("E2:G$e").NumberFormat = '#,##0'; $wsSum.Range("I2:I$e").NumberFormat = '#,##0'; $wsSum.Range("K2:K$e").NumberFormat = '#,##0'
    $wsSum.Range("H2:H$e").NumberFormat = '0.00"배"'; $wsSum.Range("J2:J$e").NumberFormat = 'yyyy-mm-dd(aaa) hh:mm'
    $wsSum.Range("L2:L$e").NumberFormat = '0.0%'
    $wsSum.Range("D2:I$e").Font.Color = 0; $wsSum.Range("J2:J$e").Font.Color = 0x7F7F7F
    $wsSum.Cells($e + 2, 1).Value2 = '※ 인구 = 인구_최소와 최대의 중간값. 원자료의 이상치의심=Y 행(API 일시 오류로 보이는 시각)은 모두 제외. 최고 기록 시각은 스크립트가 원자료에서 찾은 값(회색), 나머지는 원자료 시트를 참조하는 수식입니다.'
    $wsSum.Cells($e + 2, 1).Font.Italic = $true
    Style-Header $wsSum $sh.Count
    $wsSum.Range("A1:M$e").AutoFilter() | Out-Null
    $wsSum.Columns.Item('A:M').ColumnWidth = 12; $wsSum.Columns.Item('B').ColumnWidth = 28; $wsSum.Columns.Item('J').ColumnWidth = 20
    $wsSum.Rows.Item(1).RowHeight = 30

    # --- 시간대별_평균 (장소 x 0~23시) ---
    $RngHr = & $rg 'E'
    $ha = New-Object 'object[,]' ($m + 1), 27
    $ha[0, 0] = '장소코드'; $ha[0, 1] = '장소명'; $ha[0, 2] = '분류'
    for ($h = 0; $h -lt 24; $h++) { $ha[0, ($h + 3)] = "$($h)시" }
    for ($i = 0; $i -lt $m; $i++) {
        $r = $i + 2; $ha[($i + 1), (0)] = $codes[$i]; $ha[($i + 1), (1)] = $places[$codes[$i]]; $ha[($i + 1), (2)] = "='장소별_요약'!C$r"
        for ($h = 0; $h -lt 24; $h++) {
            $ha[($i + 1), ($h + 3)] = "=IFERROR(AVERAGEIFS($RngMid,$RngCode,`$A$r,$RngHr,$h,$OK),`"`")"
        }
    }
    Write-Block $wsHr $ha ($m + 1) 27
    $wsHr.Range("D2:AA$e").NumberFormat = '#,##0'
    $cs = $wsHr.Range("D2:AA$e").FormatConditions.AddColorScale(2)
    $cs.ColorScaleCriteria.Item(1).FormatColor.Color = 0xFFFFFF; $cs.ColorScaleCriteria.Item(2).FormatColor.Color = 0x3A7BF8
    $wsHr.Cells($e + 2, 1).Value2 = '※ 각 칸 = 그 장소·그 시각(정각·30분 등 그 시간대 모든 기록)의 인구 중간값 평균. 원자료 시트를 참조하는 수식입니다.'
    $wsHr.Cells($e + 2, 1).Font.Italic = $true
    Style-Header $wsHr 27
    $wsHr.Columns.Item('A').ColumnWidth = 10; $wsHr.Columns.Item('B').ColumnWidth = 28; $wsHr.Columns.Item('C').ColumnWidth = 12
    $wsHr.Columns.Item('D:AA').ColumnWidth = 7.5

    # --- 출처 ---
    $made = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    $period = "$($first.ToString('yyyy-MM-dd HH:mm')) ~ $($lastT.ToString('yyyy-MM-dd HH:mm'))"
    $periodShort = "$($first.ToString('yyyy.MM.dd'))~$($lastT.ToString('yyyy.MM.dd'))"
    $src = @(
        @('서울 실시간 유동인구 데이터 - 출처 및 설명', ''),
        @('', ''),
        @('[출처]', ''),
        @('데이터명', '서울시 실시간 도시데이터 (실시간 인구현황 LIVE_PPLTN_STTS)'),
        @('제공기관 / 저작권자', '서울특별시 (데이터전략과)'),
        @('제공처', '서울 열린데이터광장 (data.seoul.go.kr)'),
        @('데이터 페이지', 'https://data.seoul.go.kr/dataList/OA-21285/A/1/datasetView.do'),
        @('실시간 도시데이터 서비스', 'https://data.seoul.go.kr/SeoulRtd/'),
        @('API 주소', 'http://openapi.seoul.go.kr:8088/{인증키}/json/citydata/1/5/{장소명}'),
        @('장소 분류 출처', 'https://data.seoul.go.kr/SeoulRtd/ (장소 목록·분류)'),
        @('이용허락', '공공누리 제1유형 (출처표시 - 상업적 이용 및 변경 가능)'),
        @('인구 산출 방식', '통신사(KT·SKT) 휴대폰 신호 데이터를 바탕으로 서울시가 추정한 값. 실제 인원을 센 숫자가 아니라 추계치이며, 범위(최소~최대)로 제공됨'),
        @('', ''),
        @('[이 파일의 수집 정보]', ''),
        @('수집 방법', '서울시 실시간 도시데이터 Open API를 30분마다 직접 호출해 저장 (collect.ps1) → 이 파일로 정리 (make_realtime_xlsx.ps1)'),
        @('수집 기간 (인구 기준시각)', $period),
        @('장소 수', "$($codes.Count)곳"),
        @('원자료 행 수', "$n 행 (장소 x 기준시각, 같은 장소·같은 시각 중복 제외)"),
        @('스냅샷 파일 수', "$($files.Count)개 (data 폴더, 빠진 시각이 있을 수 있음)"),
        @('파일 만든 시각', $made),
        @('참고', '서울시는 실시간 데이터를 과거분으로 따로 제공하지 않음 → 이 기간 데이터는 직접 수집한 기록'),
        @('', ''),
        @('[유튜브 설명란에 붙여넣을 출처 문구]', ''),
        @('짧은 버전', "출처: 서울특별시, 서울 열린데이터광장 「서울시 실시간 도시데이터」 (공공누리 제1유형) / 직접 수집·가공 $periodShort"),
        @('긴 버전', "자료 출처: 서울특별시 · 서울 열린데이터광장 「서울시 실시간 도시데이터」 실시간 인구현황 (https://data.seoul.go.kr/dataList/OA-21285/A/1/datasetView.do), 공공누리 제1유형. $periodShort 기간 30분 간격으로 직접 수집해 가공했으며, 인구는 통신 데이터 기반 추정치(최소~최대의 중간값)입니다."),
        @('영상 화면 하단용', '자료: 서울시 실시간 도시데이터(서울 열린데이터광장)'),
        @('', ''),
        @('[시트 설명]', ''),
        @('원자료', '장소 x 기준시각 한 줄. 필터로 날짜·장소·요일을 골라 볼 수 있음'),
        @('장소별_요약', '장소별 관측횟수·평균·평일/주말 평균·최고/최저·붐빔 비율·순위 (원자료를 참조하는 수식)'),
        @('시간대별_평균', '장소 x 0~23시 평균 인구 (색이 진할수록 많음, 수식)'),
        @('', ''),
        @('[원자료 칸 설명]', ''),
        @('기준시각', 'PPLTN_TIME - 인구 집계 기준 시각 (수집 시각보다 약 30분 이전)'),
        @('혼잡도', 'AREA_CONGEST_LVL - 여유 / 보통 / 약간 붐빔 / 붐빔 (서울시 기준)'),
        @('인구_최소 / 인구_최대', 'AREA_PPLTN_MIN / AREA_PPLTN_MAX - 추정 인구 범위'),
        @('인구_중간값', '(최소+최대)/2 - 이 파일에서 계산한 값 (원 데이터에는 없음)'),
        @('남성/여성(%)', 'MALE_PPLTN_RATE / FEMALE_PPLTN_RATE'),
        @('0~9세 ~ 70대이상(%)', 'PPLTN_RATE_0 ~ PPLTN_RATE_70 - 연령대 비율'),
        @('상주/비상주인구(%)', 'RESNT_PPLTN_RATE / NON_RESNT_PPLTN_RATE - 그 지역 거주자 비율 / 방문자 비율'),
        @('대체데이터여부', 'REPLACE_YN - Y면 통신 장애 등으로 대체된 값'),
        @('원본파일 / 수집시각', '이 줄이 들어 있던 data 폴더의 파일과 실제 API 호출 시각'),
        @('이상치의심', "Y = 그 시각 전체 장소 평균이 앞뒤 1시간 30분(3개 시각)의 중앙값보다 1.6배 이상 크거나 0.6배 이하 → API 일시 오류로 보고 요약·시간대 시트에서 제외 (이번 파일: $($outlier.Count)개 시각)")
    )
    $sr = New-Object 'object[,]' $src.Count, 2
    for ($i = 0; $i -lt $src.Count; $i++) { $sr[$i, 0] = $src[$i][0]; $sr[$i, 1] = $src[$i][1] }
    $rs = $wsSrc.Range($wsSrc.Cells(1, 1), $wsSrc.Cells($src.Count, 2)); $rs.NumberFormat = '@'; $rs.Value2 = $sr
    $wsSrc.Columns.Item('A').ColumnWidth = 30; $wsSrc.Columns.Item('B').ColumnWidth = 110
    $wsSrc.Range("B1:B$($src.Count)").WrapText = $true; $wsSrc.Range("A1:B$($src.Count)").VerticalAlignment = -4160
    $wsSrc.Cells(1, 1).Font.Size = 14; $wsSrc.Cells(1, 1).Font.Bold = $true
    for ($i = 0; $i -lt $src.Count; $i++) {
        $a = $src[$i][0]
        if ($a.StartsWith('[')) { $c = $wsSrc.Cells($i + 1, 1); $c.Font.Bold = $true; $c.Font.Color = 0x6B3A1F }
        elseif ($a -and $src[$i][1]) { $wsSrc.Cells($i + 1, 1).Font.Bold = $true }
        if ($src[$i][1] -like 'http*') { $wsSrc.Hyperlinks.Add($wsSrc.Cells($i + 1, 2), ($src[$i][1] -split ' ')[0]) | Out-Null }
    }
    foreach ($i in 0..($src.Count - 1)) { if ($src[$i][0] -in @('짧은 버전', '긴 버전', '영상 화면 하단용')) { $wsSrc.Cells($i + 1, 2).Interior.Color = 0xCCF2FF } }

    $xl.Calculation = -4105   # 자동 계산으로 되돌림
    $xl.CalculateFull()
    $wsSrc.Activate()
    if (Test-Path $xf) { Remove-Item $xf }
    $wb.SaveAs($xf, 51)
    $wb.Close($false)
    "저장: $xf"
} finally {
    $xl.Quit()
    [Runtime.InteropServices.Marshal]::ReleaseComObject($xl) | Out-Null
}
