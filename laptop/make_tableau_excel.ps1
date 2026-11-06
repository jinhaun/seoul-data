# Tableau에 바로 넣는 엑셀 파일(태블로_외국인분석\외국인관광_Tableau.xlsx)을 만듭니다.
# 시트 하나 = 차트 하나. 시트마다 값이 미리 계산돼 있어 관계(Relationship) 연결이 필요 없습니다.
#   1_외국인_생활인구 : 자치구 × 시간구간 × 날짜유형 × 국적별 평균 인구
#   2_지도            : 관광지(명소·쇼핑·음식점)와 1~9호선 지하철역을 한 시트에 (점 지도)
#   3_구별_요약       : 자치구 하나 = 한 줄 (외국인 인구, 관광지 수, 역 수)
# 먼저 make_tableau_data.ps1, make_subway_csv.ps1, geocode_places.ps1 을 실행해 두세요. 엑셀이 설치돼 있어야 합니다.

$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Dir     = Join-Path $Root '태블로_외국인분석'
$OutFile = Join-Path $Dir '외국인관광_Tableau.xlsx'
$Font    = '맑은 고딕'

. (Join-Path $Root 'tableau_settings.ps1')   # 국적, 공휴일, 시간구간 설정

$Countries = $TopCountries + '기타'
$Buckets   = '1.새벽(0~5시)','2.오전(6~11시)','3.오후(12~17시)','4.밤(18~23시)'
$DayTypes  = '평일','주말','공휴일'
$AllDay    = '0.하루 전체'
$AllType   = '전체'

function Open-Shared($path) {   # Tableau·엑셀에서 열려 있어도 읽기
    New-Object System.IO.StreamReader((New-Object System.IO.FileStream($path, 'Open', 'Read', 'ReadWrite')), [System.Text.Encoding]::UTF8)
}
function Read-Csv($path) { $r = Open-Shared $path; try { $r.ReadToEnd() | ConvertFrom-Csv } finally { $r.Close() } }

# ---------- 1) 외국인 생활인구 합본 집계 ----------
$sum = @{}      # "날짜유형|시간구간|자치구|국적" -> 인구 합
$slots = @{}    # "날짜 시간" -> "날짜유형|시간구간"  (평균 낼 때 나누는 수)
$reader = Open-Shared (Join-Path $Root '외국인_관광\합본\외국인생활인구_단기_전체.csv')
$header = Split-CsvLine $reader.ReadLine()
$idx = @{}; for ($i = 0; $i -lt $header.Count; $i++) { $idx[$header[$i]] = $i }
$countryCols = $header[7..($header.Count - 1)]
$guSet = @{}
while ($null -ne ($line = $reader.ReadLine())) {
    $v = Split-CsvLine $line
    $date = $v[$idx['날짜']]; $gu = $v[$idx['자치구']]
    $t = DayType $date $v[$idx['요일']]; $b = TimeBucket ([int]$v[$idx['시간']])
    $slots["$date $($v[$idx['시간']])"] = "$t|$b"; $guSet[$gu] = 1
    foreach ($c in $countryCols) {
        if (-not $v[$idx[$c]]) { continue }
        $pop = [double]$v[$idx[$c]]; $nat = if ($TopCountries -contains $c) { $c } else { '기타' }
        foreach ($tt in $t, $AllType) { foreach ($bb in $b, $AllDay) { $sum["$tt|$bb|$gu|$nat"] += $pop } }
    }
}
$reader.Close()
$period = ($slots.Keys | ForEach-Object { $_.Split(' ')[0] } | Sort-Object -Unique)

$cnt = @{}
foreach ($s in $slots.Values) { $t, $b = $s.Split('|'); foreach ($tt in $t, $AllType) { foreach ($bb in $b, $AllDay) { $cnt["$tt|$bb"]++ } } }
function Avg($t, $b, $gu, $nat) { [math]::Round($sum["$t|$b|$gu|$nat"] / $cnt["$t|$b"], 1) }
function AvgAll($t, $b, $gu) { [math]::Round(($Countries | ForEach-Object { $sum["$t|$b|$gu|$_"] } | Measure-Object -Sum).Sum / $cnt["$t|$b"], 1) }
$Gus = $guSet.Keys | Sort-Object

# ---------- 2) 자치구 중심 좌표 (경계에서 가장 큰 영역의 무게중심) ----------
$center = @{}
$r = Open-Shared (Join-Path $Dir '자치구_경계.geojson'); $geo = $r.ReadToEnd() | ConvertFrom-Json; $r.Close()
foreach ($f in $geo.features) {
    if ($f.geometry.type -eq 'Polygon') { $polys = @(, $f.geometry.coordinates) } else { $polys = $f.geometry.coordinates }
    $best = $null
    foreach ($p in $polys) {
        $ring = $p[0]; $a = 0.0; $cx = 0.0; $cy = 0.0
        for ($i = 0; $i -lt $ring.Count - 1; $i++) {
            $x0 = [double]$ring[$i][0]; $y0 = [double]$ring[$i][1]; $x1 = [double]$ring[$i + 1][0]; $y1 = [double]$ring[$i + 1][1]
            $k = $x0 * $y1 - $x1 * $y0; $a += $k; $cx += ($x0 + $x1) * $k; $cy += ($y0 + $y1) * $k
        }
        if (-not $best -or [math]::Abs($a) -gt [math]::Abs($best.a)) { $best = @{ a = $a; lon = $cx / (3 * $a); lat = $cy / (3 * $a) } }
    }
    $center[$f.properties.자치구] = $best
}

# ---------- 3) 시트 데이터 ----------
# 1_외국인_생활인구
$popCols = @(@('자치구','@'), @('시간구간','@'), @('날짜유형','@'), @('국적','@'), @('평균인구','#,##0'), @('위도','0.000000'), @('경도','0.000000'))
$pop = foreach ($gu in $Gus) { foreach ($b in $Buckets) { foreach ($t in $DayTypes) { foreach ($c in $Countries) {
    [pscustomobject]@{ 자치구 = $gu; 시간구간 = $b; 날짜유형 = $t; 국적 = $c; 평균인구 = Avg $t $b $gu $c; 위도 = $center[$gu].lat; 경도 = $center[$gu].lon } } } } }

# 2_지도 : 관광지 + 지하철역
$places = Read-Csv (Join-Path $Dir '관광지_목록.csv') | Where-Object { $_.위도 }

# 영문판: 소개페이지 주소 끝의 ID(KOPxxxx / ENPxxxx 의 xxxx)가 같으면 같은 장소
function PageId($u) { if ($u -match '/[A-Za-z]{3}([A-Za-z0-9]+)\?') { $Matches[1] } }
$english = @{}
foreach ($kind in '명소', '쇼핑', '음식점') {
    foreach ($e in (Read-Csv (Join-Path $Root "외국인_공공데이터\관광_${kind}_5개언어.csv") | Where-Object LANG_CODE_ID -eq 'en')) {
        $k = PageId $e.POST_URL; if ($k) { $english[$k] = $e }
    }
}

# 장소마다 그 구의 외국인 평균 인구 (도구 설명용)
$guPop = @{}
foreach ($gu in $Gus) { $guPop[$gu] = [ordered]@{ 하루 = AvgAll $AllType $AllDay $gu }; foreach ($b in $Buckets) { $guPop[$gu][($b -replace '^\d\.', '' -replace '\(.*', '')] = AvgAll $AllType $b $gu } }
$stations = [ordered]@{}; $subwayEn = @{}
foreach ($s in (Read-Csv (Join-Path $Dir '지하철_1~9호선.csv'))) {
    if ($s.자치구 -eq '서울 밖') { continue }
    if (-not $subwayEn[$s.역]) { $subwayEn[$s.역] = $s.영문역명 }
    if (-not $stations.Contains($s.역)) { $stations[$s.역] = [ordered]@{ 역 = $s.역; 자치구 = $s.자치구; 위도 = $s.위도; 경도 = $s.경도; 호선 = @() } }
    if ($stations[$s.역].호선 -notcontains $s.호선) { $stations[$s.역].호선 += $s.호선 }
}
$mapCols = @(@('구분','@'), @('이름','@'), @('영문명','@'), @('자치구','@'), @('위도','0.000000'), @('경도','0.000000'), @('호선','@'), @('환승역','@'),
             @('주소','@'), @('가까운_지하철','@'), @('운영시간','@'), @('휴무일','@'), @('홈페이지','@'), @('소개페이지','@'), @('영문_소개페이지','@'),
             @('구_외국인_하루평균','#,##0'), @('구_외국인_새벽','#,##0'), @('구_외국인_오전','#,##0'), @('구_외국인_오후','#,##0'), @('구_외국인_밤','#,##0'))
function Add-GuPop($o, $gu) { if ($guPop[$gu]) { $o.구_외국인_하루평균 = $guPop[$gu].하루; foreach ($k in '새벽', '오전', '오후', '밤') { $o["구_외국인_$k"] = $guPop[$gu][$k] } }; [pscustomobject]$o }
$map = @(foreach ($p in $places) {
    $e = $english[(PageId $p.소개페이지)]
    Add-GuPop ([ordered]@{ 구분 = $p.종류; 이름 = $p.관광지; 영문명 = $e.POST_SJ; 자치구 = $p.자치구; 위도 = [double]$p.위도; 경도 = [double]$p.경도
                           주소 = $p.주소; 가까운_지하철 = $p.가까운_지하철; 운영시간 = $p.운영시간; 휴무일 = $p.휴무일; 홈페이지 = $p.홈페이지
                           소개페이지 = ($p.소개페이지 -replace '\?.*$', ''); 영문_소개페이지 = ($e.POST_URL -replace '\?.*$', '') }) $p.자치구
}) + @(foreach ($s in $stations.Values) {
    $en = ($subwayEn[$s.역])
    Add-GuPop ([ordered]@{ 구분 = '지하철역'; 이름 = $s.역; 영문명 = $en; 자치구 = $s.자치구; 위도 = [double]$s.위도; 경도 = [double]$s.경도
                           호선 = ($s.호선 | Sort-Object) -join ', '; 환승역 = $(if ($s.호선.Count -gt 1) { 'Y' } else { 'N' }) }) $s.자치구
})

# 3_구별_요약
$sumCols = @(@('자치구','@'), @('위도','0.000000'), @('경도','0.000000'), @('하루_평균인구','#,##0')) +
    ($Buckets | ForEach-Object { , @((($_ -replace '^\d\.', '' -replace '\(.*', '') + '_평균인구'), '#,##0') }) +
    ($DayTypes | ForEach-Object { , @(($_ + '_평균인구'), '#,##0') }) + @(
    @('명소_수','0'), @('쇼핑_수','0'), @('음식점_수','0'), @('관광지_합계','0'), @('지하철역_수','0'), @('지나는_호선','@'))
$summary = foreach ($gu in $Gus) {
    $o = [ordered]@{ 자치구 = $gu; 위도 = $center[$gu].lat; 경도 = $center[$gu].lon; 하루_평균인구 = AvgAll $AllType $AllDay $gu }
    foreach ($b in $Buckets) { $o[($b -replace '^\d\.', '' -replace '\(.*', '') + '_평균인구'] = AvgAll $AllType $b $gu }
    foreach ($t in $DayTypes) { $o[$t + '_평균인구'] = AvgAll $t $AllDay $gu }
    $mine = @($map | Where-Object 자치구 -eq $gu)
    foreach ($k in '명소', '쇼핑', '음식점') { $o["${k}_수"] = @($mine | Where-Object 구분 -eq $k).Count }
    $o.관광지_합계 = $o.명소_수 + $o.쇼핑_수 + $o.음식점_수
    $st = @($mine | Where-Object 구분 -eq '지하철역'); $o.지하철역_수 = $st.Count
    $o.지나는_호선 = (($st | ForEach-Object { $_.호선 -split ', ' }) | Sort-Object -Unique) -join ', '
    [pscustomobject]$o
}

# ---------- 4) 설명 시트 ----------
$notes = @(
    @('시트', '무엇에 쓰나', '만드는 법 (예시)', '주의'),
    @('1_외국인_생활인구', '언제(시간구간·평일/주말/공휴일), 어느 구에, 어느 나라 외국인이 많은지', '히트맵: 행=자치구, 열=날짜유형·시간구간, 색상=평균인구, 마크=사각형' + "`n" + '지도: 위도·경도를 더블클릭 → 세부정보=자치구, 크기·색상=평균인구, 필터=시간구간·날짜유형' + "`n" + '막대: 행=국적, 열=평균인구', '날짜유형과 시간구간은 항상 행·열·필터 중 어딘가에 두세요(필터는 하나만 선택). 빼면 여러 칸이 더해져 숫자가 커집니다. 자치구·국적은 빼도 괜찮습니다(합계가 됨).'),
    @('2_지도', '외국인용 관광지(명소·쇼핑·음식점)와 1~9호선 지하철역 위치', '위도·경도를 더블클릭 → 세부정보=이름, 색상=구분, 마크=원' + "`n" + '필터=구분 으로 관광지·역을 골라 보기, 도구 설명에 주소·운영시간·가까운_지하철', '한 줄 = 장소 하나. 지하철역은 환승역도 한 번만 있고 [호선]에 여러 호선이 적혀 있습니다. 구_외국인_* 은 그 장소가 있는 구의 외국인 평균 인구라 도구 설명에만 쓰세요(더하면 커짐).'),
    @('3_구별_요약', '구마다 외국인 인구와 관광지·역 수 비교 (산점도, 순위 막대)', '산점도: 열=관광지_합계, 행=오후_평균인구, 세부정보·레이블=자치구' + "`n" + '순위: 행=자치구, 열=하루_평균인구, 내림차순 정렬', '한 줄 = 구 하나라 어떻게 끌어놓아도 숫자가 맞습니다.'),
    @('', '', '', ''),
    @('평균인구', '그 시간에 그 구에 머물던 단기 체류 외국인 수의 평균 (방문자 수가 아님)', "기간: $($period[0]) ~ $($period[-1])", '공휴일은 주말과 겹쳐도 공휴일로 분류. 국적은 상위 6개 + 기타.'),
    @('출처', '서울 열린데이터광장: 생활인구(단기체류 외국인), visitseoul 관광정보, 지하철역 정보', '관광지 좌표: OpenStreetMap Nominatim (주소로 찾은 값이라 일부는 근처 위치일 수 있음)', '자치구 중심: southkorea/seoul-maps')
)

# ---------- 5) 엑셀로 쓰기 ----------
function Cell($v) {
    if ($v -eq $null) { return $null }
    if ($v -is [string]) { if ($v -eq '') { return $null } else { return [string]$v } }
    return [double]$v
}
function Write-Sheet($ws, $name, $colSpec, $data) {
    $ws.Name = $name
    $data = [object[]]@(foreach ($d in $data) { $d }); $nR = $data.Count + 1; $nC = $colSpec.Count
    $arr = New-Object 'object[,]' $nR, $nC
    for ($c = 0; $c -lt $nC; $c++) { $arr[0, $c] = [string]$colSpec[$c][0] }
    for ($i = 1; $i -lt $nR; $i++) { for ($c = 0; $c -lt $nC; $c++) { $arr[$i, $c] = Cell $data[$i - 1].($colSpec[$c][0]) } }
    for ($c = 0; $c -lt $nC; $c++) { $ws.Range($ws.Cells(2, $c + 1), $ws.Cells([math]::Max($nR, 2), $c + 1)).NumberFormat = $colSpec[$c][1] }
    $range = $ws.Range($ws.Cells(1, 1), $ws.Cells($nR, $nC))
    $range.Value2 = $arr
    $range.Font.Name = $Font; $range.Font.Size = 10
    $hdr = $ws.Range($ws.Cells(1, 1), $ws.Cells(1, $nC)); $hdr.Font.Bold = $true; $hdr.Interior.Color = 0xEBE3DA
    $range.AutoFilter() | Out-Null
    $ws.Columns.AutoFit() | Out-Null
    foreach ($c in 1..$nC) { if ($ws.Columns.Item($c).ColumnWidth -gt 45) { $ws.Columns.Item($c).ColumnWidth = 45 } }
}

$xl = New-Object -ComObject Excel.Application
$xl.Visible = $false; $xl.DisplayAlerts = $false; $xl.ScreenUpdating = $false
try {
    $wb = $xl.Workbooks.Add()
    while ($wb.Worksheets.Count -lt 4) { $wb.Worksheets.Add([Type]::Missing, $wb.Worksheets.Item($wb.Worksheets.Count)) | Out-Null }

    $ws = $wb.Worksheets.Item(1); $ws.Name = '설명'
    $arr = New-Object 'object[,]' $notes.Count, 4
    for ($i = 0; $i -lt $notes.Count; $i++) { for ($c = 0; $c -lt 4; $c++) { $arr[$i, $c] = $notes[$i][$c] } }
    $range = $ws.Range($ws.Cells(1, 1), $ws.Cells($notes.Count, 4))
    $range.Value2 = $arr; $range.Font.Name = $Font; $range.Font.Size = 10; $range.VerticalAlignment = -4160   # 위쪽 맞춤
    $ws.Range('A1:D1').Font.Bold = $true; $ws.Range('A1:D1').Interior.Color = 0xEBE3DA
    $ws.Columns.Item(1).ColumnWidth = 18; $ws.Columns.Item(2).ColumnWidth = 40; $ws.Columns.Item(3).ColumnWidth = 70; $ws.Columns.Item(4).ColumnWidth = 55
    $range.WrapText = $true

    Write-Sheet $wb.Worksheets.Item(2) '1_외국인_생활인구' $popCols $pop
    Write-Sheet $wb.Worksheets.Item(3) '2_지도' $mapCols $map
    Write-Sheet $wb.Worksheets.Item(4) '3_구별_요약' $sumCols $summary

    foreach ($n in 2..4) {
        $wb.Worksheets.Item($n).Activate()
        $xl.ActiveWindow.SplitRow = 1; $xl.ActiveWindow.SplitColumn = 0; $xl.ActiveWindow.FreezePanes = $true
    }
    $wb.Worksheets.Item(1).Activate()

    if (Test-Path $OutFile) { Remove-Item $OutFile }
    $wb.SaveAs($OutFile, 51)
    $wb.Close($false)
} finally {
    $xl.Quit()
    [Runtime.InteropServices.Marshal]::ReleaseComObject($xl) | Out-Null
}
"저장: $OutFile"
"1_외국인_생활인구 $(@($pop).Count)줄 / 2_지도 $($map.Count)줄 (관광지 $(@($places).Count), 역 $($stations.Count)) / 3_구별_요약 $(@($summary).Count)줄"
