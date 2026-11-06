# 관광명소 대시보드용 엑셀(바탕화면\외국인 프로젝트\외국인관광_대시보드.xlsx)을 만듭니다.
#   1_관광명소          : 지도에 찍을 명소 (한 줄 = 명소 하나)
#   2_주변_지하철역     : 명소마다 가까운 1~9호선 역 (1km 안 최대 5개, 없으면 가장 가까운 역 1개)
#   3_외국인_시간대별   : 명소가 있는 행정동의 단기 체류 외국인 (날짜 × 시간, 한 줄 = 동·날짜·시간 하나)
# Tableau 대시보드에서 1번 지도를 클릭하면 [명소ID]로 2번을, [행정동코드]로 3번을 거르는(동작 필터) 구조입니다.
# 먼저 geocode_places.ps1 -Kinds 명소, make_subway_csv.ps1 을 실행해 두세요. 엑셀이 설치돼 있어야 합니다.
# -AllNat 을 붙이면 3번 시트에 원본의 모든 국적을 칸으로 넣고, 최종_데이터\외국인관광_대시보드_전체국적.xlsx 로 저장 (원래 파일은 그대로)
param([switch]$AllNat)

$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$OutDir  = Join-Path ([Environment]::GetFolderPath('Desktop')) '외국인 프로젝트'
$OutFile = Join-Path $OutDir '외국인관광_대시보드.xlsx'
if ($AllNat) { $OutDir = Join-Path $Root '최종_데이터'; $OutFile = Join-Path $OutDir '외국인관광_대시보드_전체국적.xlsx' }
$Font    = '맑은 고딕'
$Utf8Bom = New-Object System.Text.UTF8Encoding($true)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $Root 'tableau_settings.ps1')   # 국적, 공휴일, 시간구간 설정

function Open-Shared($path) {   # Tableau·엑셀에서 열려 있어도 읽기
    New-Object System.IO.StreamReader((New-Object System.IO.FileStream($path, 'Open', 'Read', 'ReadWrite')), [System.Text.Encoding]::UTF8)
}
function Read-Csv($path) { $r = Open-Shared $path; try { $r.ReadToEnd() | ConvertFrom-Csv } finally { $r.Close() } }
function PageId($u) { if ($u -match '/[A-Za-z]{3}([A-Za-z0-9]+)\?') { $Matches[1] } }

# ---------- 1) 행정동 경계 (vuski/admdongkor, 서울만 저장해 두고 재사용) ----------
Add-Type -AssemblyName System.Web.Extensions
$ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer; $ser.MaxJsonLength = [int]::MaxValue
$DongFile = Join-Path $Root '외국인_공공데이터\행정동_경계_서울.geojson'
if (-not (Test-Path $DongFile)) {
    $tmp = Join-Path $env:TEMP 'admdong_kr.geojson'
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest 'https://raw.githubusercontent.com/vuski/admdongkor/master/ver20261001/HangJeongDong_ver20261001.geojson' -OutFile $tmp -UseBasicParsing
    $all = $ser.DeserializeObject([IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8))
    $keep = New-Object System.Collections.Generic.List[object]
    foreach ($f in $all['features']) { if ("$($f['properties']['adm_cd2'])".StartsWith('11')) { $keep.Add($f) } }
    $fc = New-Object 'System.Collections.Generic.Dictionary[string,object]'; $fc['type'] = 'FeatureCollection'; $fc['features'] = $keep.ToArray()
    [IO.File]::WriteAllText($DongFile, $ser.Serialize($fc), (New-Object System.Text.UTF8Encoding($false)))
    Remove-Item $tmp
}
$dongGeo = $ser.DeserializeObject([IO.File]::ReadAllText($DongFile, [Text.Encoding]::UTF8))

$dongs = foreach ($f in $dongGeo['features']) {
    $pr = $f['properties']; $g = $f['geometry']
    if ($g['type'] -eq 'Polygon') { $polys = @(, $g['coordinates']) } else { $polys = $g['coordinates'] }
    $rings = New-Object System.Collections.Generic.List[object]
    foreach ($p in $polys) { $rings.Add($p[0]) }   # 바깥 테두리만
    $xs = foreach ($ring in $rings) { foreach ($pt in $ring) { [double]$pt[0] } }
    $ys = foreach ($ring in $rings) { foreach ($pt in $ring) { [double]$pt[1] } }
    [pscustomobject]@{ 코드 = "$($pr['adm_cd2'])".Substring(0, 8); 이름 = ($pr['adm_nm'] -split ' ')[-1]; 자치구 = $pr['sggnm']; Rings = $rings
                       MinX = ($xs | Measure-Object -Minimum).Minimum; MaxX = ($xs | Measure-Object -Maximum).Maximum
                       MinY = ($ys | Measure-Object -Minimum).Minimum; MaxY = ($ys | Measure-Object -Maximum).Maximum }
}
function In-Ring($ring, [double]$x, [double]$y) {
    $in = $false; $n = $ring.Count; $j = $n - 1
    for ($i = 0; $i -lt $n; $i++) {
        $xi = [double]$ring[$i][0]; $yi = [double]$ring[$i][1]; $xj = [double]$ring[$j][0]; $yj = [double]$ring[$j][1]
        if ((($yi -gt $y) -ne ($yj -gt $y)) -and ($x -lt ($xj - $xi) * ($y - $yi) / ($yj - $yi) + $xi)) { $in = -not $in }
        $j = $i
    }
    $in
}
function Find-Dong([double]$lon, [double]$lat) {
    foreach ($d in $dongs) {
        if ($lon -lt $d.MinX -or $lon -gt $d.MaxX -or $lat -lt $d.MinY -or $lat -gt $d.MaxY) { continue }
        foreach ($ring in $d.Rings) { if (In-Ring $ring $lon $lat) { return $d } }
    }
    $null
}
$dongByCode = @{}; foreach ($d in $dongs) { $dongByCode[$d.코드] = $d }
"행정동 경계: $(@($dongs).Count) 개"

# ---------- 2) 관광명소 ----------
$english = @{}
foreach ($e in (Read-Csv (Join-Path $Root '외국인_공공데이터\관광_명소_5개언어.csv') | Where-Object LANG_CODE_ID -eq 'en')) { $k = PageId $e.POST_URL; if ($k) { $english[$k] = $e } }

$spots = New-Object System.Collections.Generic.List[object]
$dropped = @()
foreach ($p in (Read-Csv (Join-Path $Root '태블로_외국인분석\관광지_목록.csv') | Where-Object { $_.종류 -eq '명소' -and $_.위도 })) {
    $lat = [double]$p.위도; $lon = [double]$p.경도
    $d = Find-Dong $lon $lat
    if (-not $d -or $d.자치구 -ne $p.자치구) { $dropped += "$($p.관광지) (주소: $($p.자치구), 찾은 위치: $(if ($d) { $d.자치구 } else { '서울 밖' }))"; continue }   # 좌표가 주소의 구와 다르면 잘못 찾은 것
    $id = PageId $p.소개페이지; $e = $english[$id]
    $spots.Add([pscustomobject][ordered]@{
        명소ID = $id; 관광명소 = $p.관광지; 영문명 = $e.POST_SJ; 자치구 = $p.자치구; 행정동 = $d.이름; 행정동코드 = [double]$d.코드
        위도 = $lat; 경도 = $lon; 주소 = $p.주소; 가까운_지하철_안내 = $p.가까운_지하철
        운영시간 = $p.운영시간; 운영요일 = $p.운영요일; 휴무일 = $p.휴무일; 전화 = $p.전화; 홈페이지 = $p.홈페이지; 태그 = $p.태그
        소개페이지 = ($p.소개페이지 -replace '\?.*$', ''); 영문_소개페이지 = ($e.POST_URL -replace '\?.*$', '')
    })
}
"관광명소: $($spots.Count) 곳 (좌표가 주소와 맞지 않아 뺀 곳 $($dropped.Count))"; $dropped | ForEach-Object { "  뺌: $_" }

# ---------- 3) 주변 지하철역 ----------
$stations = [ordered]@{}
foreach ($s in (Read-Csv (Join-Path $Root '태블로_외국인분석\지하철_1~9호선.csv'))) {
    if (-not $stations.Contains($s.역)) { $stations[$s.역] = [pscustomobject]@{ 역 = $s.역; 영문 = $s.영문역명; 위도 = [double]$s.위도; 경도 = [double]$s.경도; 호선 = New-Object System.Collections.Generic.List[string] } }
    if (-not $stations[$s.역].호선.Contains($s.호선)) { $stations[$s.역].호선.Add($s.호선) }
}
function Meters([double]$lat1, [double]$lon1, [double]$lat2, [double]$lon2) {
    $r = 6371000; $dLat = ($lat2 - $lat1) * [math]::PI / 180; $dLon = ($lon2 - $lon1) * [math]::PI / 180
    $a = [math]::Pow([math]::Sin($dLat / 2), 2) + [math]::Cos($lat1 * [math]::PI / 180) * [math]::Cos($lat2 * [math]::PI / 180) * [math]::Pow([math]::Sin($dLon / 2), 2)
    2 * $r * [math]::Asin([math]::Sqrt($a))
}
$near = New-Object System.Collections.Generic.List[object]
foreach ($sp in $spots) {
    $ds = foreach ($st in $stations.Values) { [pscustomobject]@{ S = $st; M = (Meters $sp.위도 $sp.경도 $st.위도 $st.경도) } }
    $ds = @($ds | Sort-Object M)
    $pick = @($ds | Where-Object { $_.M -le 1000 } | Select-Object -First 5); if (-not $pick.Count) { $pick = @($ds[0]) }
    $sp | Add-Member 가장_가까운_역 $pick[0].S.역
    $sp | Add-Member 가장_가까운_역_거리_m ([math]::Round($pick[0].M))
    $rank = 0
    foreach ($x in $pick) {
        $rank++
        $near.Add([pscustomobject][ordered]@{
            명소ID = $sp.명소ID; 관광명소 = $sp.관광명소; 순위 = $rank; 역 = $x.S.역; 영문역명 = $x.S.영문
            호선 = (($x.S.호선 | Sort-Object) -join ', '); 거리_m = [math]::Round($x.M); 도보_분 = [math]::Max(1, [math]::Round($x.M / 70))
            역_위도 = $x.S.위도; 역_경도 = $x.S.경도
        })
    }
}
"주변 지하철역: $($near.Count) 줄"

# ---------- 4) 행정동 시간대별 단기 체류 외국인 ----------
$needDong = @{}; foreach ($sp in $spots) { $needDong["$([int64]$sp.행정동코드)"] = 1 }
$natCode = [ordered]@{ CHN = '중국'; THA = '태국'; USA = '미국'; JPN = '일본'; MNG = '몽골'; VNM = '베트남' }
if ($AllNat) {   # 자치구 외국인 데이터와 같은 순서
    $natCode = [ordered]@{ CHN = '중국'; JPN = '일본'; USA = '미국'; THA = '태국'; VNM = '베트남'; PHL = '필리핀'; IDN = '인도네시아'; MNG = '몽골'
        RUS = '러시아'; KAZ = '카자흐스탄'; UZB = '우즈베키스탄'; CAN = '캐나다'; FRA = '프랑스'; IND = '인도'; NPL = '네팔'; LKA = '스리랑카'
        KHM = '캄보디아'; PAK = '파키스탄' }
}
$dowKo = @{ Monday = '월'; Tuesday = '화'; Wednesday = '수'; Thursday = '목'; Friday = '금'; Saturday = '토'; Sunday = '일' }
$popCsv = Join-Path $env:TEMP '외국인_시간대별_tmp.csv'
$w = New-Object System.IO.StreamWriter($popCsv, $false, $Utf8Bom)
$w.WriteLine('행정동코드,행정동,자치구,날짜,월,요일,날짜유형,공휴일명,시간,시간구간,외국인_합계,' + (($natCode.Values + '기타') -join ','))
$popRows = 0; $dongSum = @{}; $dongCnt = @{}; $firstDate = $null; $lastDate = $null
foreach ($f in (Get-ChildItem (Join-Path $Root '외국인_공공데이터\생활인구_행정동별_단기외국인') -Filter '*.csv' | Sort-Object Name)) {
    $r = Open-Shared $f.FullName
    $h = Split-CsvLine $r.ReadLine(); $ix = @{}; for ($i = 0; $i -lt $h.Count; $i++) { $ix[$h[$i]] = $i }
    while ($null -ne ($line = $r.ReadLine())) {
        if (-not $needDong.ContainsKey($line.Substring(17, 8))) { continue }   # "YYYYMMDD","HH","동코드8자리" 순서라 빠르게 거름
        $v = Split-CsvLine $line
        $code = $v[$ix['H_DNG_CD']]; if (-not $needDong.ContainsKey($code)) { continue }
        $ymd = $v[$ix['YMD']]; $date = "$($ymd.Substring(0,4))-$($ymd.Substring(4,2))-$($ymd.Substring(6,2))"
        $dt = [datetime]::ParseExact($ymd, 'yyyyMMdd', $null); $dow = $dowKo["$($dt.DayOfWeek)"]
        $hour = [int]$v[$ix['TT']]; $tot = [double]$v[$ix['SPOP']]
        $nats = foreach ($c in $natCode.Keys) { $x = if ($ix.ContainsKey($c)) { $v[$ix[$c]] }; if ($x -and $x -ne '*') { [double]$x } else { 0 } }
        $etc = [math]::Max(0, $tot - ($nats | Measure-Object -Sum).Sum)
        $d = $dongByCode[$code]
        $w.WriteLine(('{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11},{12}' -f $code, $d.이름, $d.자치구, $date, $dt.Month, $dow, (DayType $date $dow), $Holidays[$date], $hour, (TimeBucket $hour), $tot, ($nats -join ','), [math]::Round($etc, 2)))
        $popRows++; $dongSum[$code] += $tot; $dongCnt[$code]++
        if (-not $firstDate -or $date -lt $firstDate) { $firstDate = $date }; if (-not $lastDate -or $date -gt $lastDate) { $lastDate = $date }
    }
    $r.Close()
}
$w.Close()
"외국인 시간대별: $popRows 줄 (행정동 $($needDong.Count) 개, $firstDate ~ $lastDate)"
foreach ($sp in $spots) { $c = "$([int64]$sp.행정동코드)"; $sp | Add-Member 동_외국인_하루평균 $(if ($dongCnt[$c]) { [math]::Round($dongSum[$c] / $dongCnt[$c]) } else { $null }) }

# ---------- 5) 설명 시트 ----------
$notes = @(
    @('시트', '내용', 'Tableau에서', '주의'),
    @('1_관광명소', "관광명소 $($spots.Count)곳. 위치, 영문명, 주소, 운영시간, 가장 가까운 역, 그 동의 외국인 하루 평균", '지도: 위도·경도 더블클릭 → 세부정보=명소ID, 관광명소 / 색상·크기=동_외국인_하루평균 / 도구 설명=주소·운영시간·가장_가까운_역', '한 줄 = 명소 하나'),
    @('2_주변_지하철역', '명소마다 가까운 1~9호선 역 (1km 안 최대 5개, 없으면 가장 가까운 1개). 직선거리와 도보 시간(분당 70m)', '표: 행=순위, 역, 호선 / 텍스트=거리_m, 도보_분', '명소를 클릭하면 이 시트가 그 명소의 역만 보이도록 [명소ID]로 동작 필터를 겁니다.'),
    @('3_외국인_시간대별', "명소가 있는 행정동의 단기 체류 외국인. 한 줄 = 행정동·날짜·시간 하나. 기간 $firstDate ~ $lastDate", '선: 열=시간, 행=외국인_합계 / 필터=날짜(범위), 날짜유형, 시간구간', '외국인_합계·국적 컬럼은 기본 집계를 반드시 [평균]으로 바꾸세요(오른쪽 클릭 → 기본 속성 → 집계 → 평균). 날짜를 여러 날 골라도 평균이라 숫자가 맞습니다.'),
    @('', '', '', ''),
    @('대시보드 연결', '명소 클릭 → 주변역·외국인 정보 바뀌기', '대시보드 → 동작 → 필터 추가: 원본=관광명소 지도, 대상=주변역 표 / 선택한 필드: 명소ID = 명소ID' + "`n" + '필터 하나 더: 대상=외국인 차트 / 선택한 필드: 행정동코드 = 행정동코드', '두 동작 모두 "선택 항목을 지우면: 모든 값 제외" 또는 "모든 값 표시" 중 원하는 쪽을 고르세요.'),
    @('외국인 수 뜻', '그 시간에 그 행정동에 머물던 단기 체류 외국인 수 (KT 통신 데이터 기반 서울시 추정치). 방문자 수가 아니라 "그 시간 그 동네에 있던 사람 수"입니다.', "국적: $(($natCode.Values + '기타') -join '·')", '국적별 값이 적으면 원본에서 * 로 가려져 있어 0으로 넣고, 그만큼은 기타에 들어갑니다.'),
    @('출처', '서울 열린데이터광장: 행정동 단위 서울 생활인구(단기체류 외국인), visitseoul 관광 명소, 서울시 역사마스터 정보, 서울교통공사 노선별 지하철역 정보', '명소 좌표: 서울시 실시간 도시데이터 장소 좌표(있는 곳) + OpenStreetMap Nominatim (© OpenStreetMap contributors) / 행정동 경계: vuski/admdongkor (2026-10-01)', '공휴일: 관공서의 공휴일에 관한 규정 (노동절·제헌절 포함)')
)

# ---------- 6) 엑셀로 쓰기 ----------
function Cell($v) {
    if ($v -eq $null) { return $null }
    if ($v -is [string]) { if ($v -eq '') { return $null } else { return [string]$v } }
    return [double]$v
}
function Style($ws) {
    $u = $ws.UsedRange; $u.Font.Name = $Font; $u.Font.Size = 10
    $hdr = $ws.Range($ws.Cells(1, 1), $ws.Cells(1, $u.Columns.Count)); $hdr.Font.Bold = $true; $hdr.Interior.Color = 0xEBE3DA
    $u.AutoFilter() | Out-Null
    $ws.Columns.AutoFit() | Out-Null
    foreach ($c in 1..$u.Columns.Count) { if ($ws.Columns.Item($c).ColumnWidth -gt 45) { $ws.Columns.Item($c).ColumnWidth = 45 } }
}
function Write-Sheet($ws, $name, $colSpec, $data) {
    $ws.Name = $name
    $data = [object[]]@(foreach ($d in $data) { $d }); $nR = $data.Count + 1; $nC = $colSpec.Count
    $arr = New-Object 'object[,]' $nR, $nC
    for ($c = 0; $c -lt $nC; $c++) { $arr[0, $c] = [string]$colSpec[$c][0] }
    for ($i = 1; $i -lt $nR; $i++) { for ($c = 0; $c -lt $nC; $c++) { $arr[$i, $c] = Cell $data[$i - 1].($colSpec[$c][0]) } }
    for ($c = 0; $c -lt $nC; $c++) { $ws.Range($ws.Cells(2, $c + 1), $ws.Cells([math]::Max($nR, 2), $c + 1)).NumberFormat = $colSpec[$c][1] }
    $ws.Range($ws.Cells(1, 1), $ws.Cells($nR, $nC)).Value2 = $arr
    Style $ws
}
$spotCols = @(@('명소ID','@'), @('관광명소','@'), @('영문명','@'), @('자치구','@'), @('행정동','@'), @('행정동코드','0'), @('위도','0.000000'), @('경도','0.000000'),
              @('동_외국인_하루평균','#,##0'), @('가장_가까운_역','@'), @('가장_가까운_역_거리_m','#,##0'), @('주소','@'), @('가까운_지하철_안내','@'),
              @('운영시간','@'), @('운영요일','@'), @('휴무일','@'), @('전화','@'), @('홈페이지','@'), @('소개페이지','@'), @('영문_소개페이지','@'), @('태그','@'))
$nearCols = @(@('명소ID','@'), @('관광명소','@'), @('순위','0'), @('역','@'), @('영문역명','@'), @('호선','@'), @('거리_m','#,##0'), @('도보_분','0'), @('역_위도','0.000000'), @('역_경도','0.000000'))

$xl = New-Object -ComObject Excel.Application
$xl.Visible = $false; $xl.DisplayAlerts = $false; $xl.ScreenUpdating = $false
try {
    $wb = $xl.Workbooks.Add()
    while ($wb.Worksheets.Count -lt 3) { $wb.Worksheets.Add([Type]::Missing, $wb.Worksheets.Item($wb.Worksheets.Count)) | Out-Null }

    $ws = $wb.Worksheets.Item(1); $ws.Name = '설명'
    $arr = New-Object 'object[,]' $notes.Count, 4
    for ($i = 0; $i -lt $notes.Count; $i++) { for ($c = 0; $c -lt 4; $c++) { $arr[$i, $c] = $notes[$i][$c] } }
    $range = $ws.Range($ws.Cells(1, 1), $ws.Cells($notes.Count, 4))
    $range.Value2 = $arr; $range.Font.Name = $Font; $range.Font.Size = 10; $range.VerticalAlignment = -4160; $range.WrapText = $true
    $ws.Range('A1:D1').Font.Bold = $true; $ws.Range('A1:D1').Interior.Color = 0xEBE3DA
    $ws.Columns.Item(1).ColumnWidth = 18; $ws.Columns.Item(2).ColumnWidth = 45; $ws.Columns.Item(3).ColumnWidth = 65; $ws.Columns.Item(4).ColumnWidth = 55

    Write-Sheet $wb.Worksheets.Item(2) '1_관광명소' $spotCols $spots
    Write-Sheet $wb.Worksheets.Item(3) '2_주변_지하철역' $nearCols $near

    # 큰 표는 CSV를 엑셀로 열어 시트째 복사 (훨씬 빠름)
    $csvWb = $xl.Workbooks.Open($popCsv)
    $csvWb.Worksheets.Item(1).Copy([Type]::Missing, $wb.Worksheets.Item($wb.Worksheets.Count))
    $csvWb.Close($false)
    $ws = $wb.Worksheets.Item($wb.Worksheets.Count); $ws.Name = '3_외국인_시간대별'
    $ws.Range('D:D').NumberFormat = 'yyyy-mm-dd'
    $ws.Range($ws.Cells(1, 11), $ws.Cells(1, 12 + $natCode.Count)).EntireColumn.NumberFormat = '#,##0.0'   # 외국인_합계 ~ 기타
    Style $ws

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
    Remove-Item $popCsv -ErrorAction SilentlyContinue
}
"저장: $OutFile"
