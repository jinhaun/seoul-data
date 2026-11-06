# 1~9호선 역 좌표와 노선 순서를 받아 태블로_외국인분석\지하철_1~9호선.csv 로 저장합니다.
# 사용: powershell -File make_subway_csv.ps1   (make_tableau_data.ps1 과 자치구_경계.geojson 이 먼저 있어야 함)
# Tableau에서 마크를 '선'으로, '경로'에 [순서], 세부정보에 [경로ID] 를 넣으면 노선이 그려집니다.

$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Out     = Join-Path $Root '태블로_외국인분석'
$Utf8    = New-Object System.Text.UTF8Encoding($false)

$ApiKey = Get-Content (Join-Path $Root 'config.txt') -Encoding UTF8 |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') -and -not $_.Contains('=') } |
    Select-Object -First 1

function Get-All($svc) {
    $rows = @(); $wc = New-Object System.Net.WebClient
    for ($s = 1; ; $s += 1000) {
        $j = $Utf8.GetString($wc.DownloadData("http://openapi.seoul.go.kr:8088/$ApiKey/json/$svc/$s/$($s + 999)/")) | ConvertFrom-Json
        if (-not $j.$svc) { break }
        $rows += $j.$svc.row
        if ($rows.Count -ge [int]$j.$svc.list_total_count) { break }
    }
    $wc.Dispose(); $rows
}

$lineInfo = Get-All 'SearchSTNBySubwayLineInfo'   # 역 외부코드(FR_CODE) = 노선 위 순서
$master   = Get-All 'subwayStationMaster'         # 역 좌표

# ---------- 노선별 경로 (외부코드 순서) ----------
$byCode = @{}
foreach ($r in $lineInfo) { if ($r.LINE_NUM -match '^0[1-9]호선$') { $byCode["$([int]$r.LINE_NUM.Substring(0,2))|$($r.FR_CODE)"] = $r } }

function Codes([int]$line, [string]$pattern) {
    # 해당 호선에서 pattern(정규식)에 맞는 외부코드를 숫자 순서로
    $byCode.Keys | Where-Object { $_ -like "$line|*" } | ForEach-Object { $_.Split('|')[1] } |
        Where-Object { $_ -match $pattern } | Sort-Object { [double]($_ -replace '^P', '' -replace '-', '.') }
}

$paths = [ordered]@{
    '1호선-본선'     = @('100-3', '100-2', '100-1') + @(Codes 1 '^\d+$')
    '1호선-경부선'   = @('141') + @(Codes 1 '^P\d+$')
    '1호선-광명'     = @('P144', 'P144-1')
    '1호선-서동탄'   = @('P157', 'P157-1')
    '2호선-순환'     = @(Codes 2 '^\d+$') + @('201')
    '2호선-성수지선' = @('211') + @(Codes 2 '^211-')
    '2호선-신정지선' = @('234') + @(Codes 2 '^234-')
    '3호선'          = @(Codes 3 '^\d+$')
    '4호선'          = @(Codes 4 '^\d+$')
    '5호선-본선'     = @(Codes 5 '^\d+$')
    '5호선-마천지선' = @('548') + @(Codes 5 '^P')
    '6호선-응암순환' = @('610', '611', '612', '613', '614', '615', '610')
    '6호선-본선'     = @('610') + @(Codes 6 '^\d+$' | Where-Object { [int]$_ -ge 616 })
    '7호선'          = @(Codes 7 '^\d+$')
    '8호선'          = @(Codes 8 '^\d+$')
    '9호선'          = @(Codes 9 '^\d+$')
}

# ---------- 역 좌표 찾기 ----------
$routeOf = @{ 1 = '1호선|경부선|경원선|경인선|장항선'; 2 = '2호선'; 3 = '3호선|일산선'; 4 = '4호선|과천선|안산선|진접선'
              5 = '5호선'; 6 = '6호선'; 7 = '7호선'; 8 = '8호선|별내선'; 9 = '9호선' }
function Norm($n) { ($n -replace '\(.*?\)', '' -replace '역$', '').Trim() }
$OldNames = @{ '자양' = '뚝섬유원지' }   # 역사마스터에 옛 이름으로 남아 있는 역
function Find-Coord([int]$line, $name) {
    $n = Norm $name
    if ($OldNames[$n]) { $n = $OldNames[$n] }
    $hit = $master | Where-Object { (Norm $_.BLDN_NM) -eq $n -and $_.ROUTE -match "^($($routeOf[$line]))" } | Select-Object -First 1
    if (-not $hit) { $hit = $master | Where-Object { (Norm $_.BLDN_NM) -eq $n } | Select-Object -First 1 }
    $hit
}

# ---------- 서울 자치구 경계 안에 있는지 ----------
$geo = Get-Content (Join-Path $Out '자치구_경계.geojson') -Raw -Encoding UTF8 | ConvertFrom-Json
function In-Ring($ring, [double]$x, [double]$y) {
    $in = $false; $n = $ring.Count; $j = $n - 1
    for ($i = 0; $i -lt $n; $i++) {
        $xi = [double]$ring[$i][0]; $yi = [double]$ring[$i][1]; $xj = [double]$ring[$j][0]; $yj = [double]$ring[$j][1]
        if ((($yi -gt $y) -ne ($yj -gt $y)) -and ($x -lt ($xj - $xi) * ($y - $yi) / ($yj - $yi) + $xi)) { $in = -not $in }
        $j = $i
    }
    $in
}
function Find-Gu([double]$lon, [double]$lat) {
    foreach ($f in $geo.features) {
        if ($f.geometry.type -eq 'Polygon') { $polys = @(, $f.geometry.coordinates) } else { $polys = $f.geometry.coordinates }
        foreach ($p in $polys) { if (In-Ring $p[0] $lon $lat) { return $f.properties.자치구 } }
    }
    $null
}

# ---------- 경로별 역 목록 (서울 안 역 + 경계 바로 바깥 역 1개씩) ----------
$result = New-Object System.Collections.Generic.List[object]
$missing = @()
foreach ($pathId in $paths.Keys) {
    $line = [int]$pathId.Substring(0, 1)
    $stops = foreach ($code in $paths[$pathId]) {
        $s = $byCode["$line|$code"]; if (-not $s) { $missing += "$pathId $code(코드 없음)"; continue }
        $c = Find-Coord $line $s.STATION_NM; if (-not $c) { $missing += "$pathId $($s.STATION_NM)(좌표 없음)"; continue }
        $gu = Find-Gu ([double]$c.LOT) ([double]$c.LAT)
        [pscustomobject]@{ 코드 = $code; 역 = $s.STATION_NM; 영문 = $s.STATION_NM_ENG; 위도 = $c.LAT; 경도 = $c.LOT; 자치구 = $gu }
    }
    $stops = @($stops)
    for ($i = 0; $i -lt $stops.Count; $i++) {
        $near = $stops[$i].자치구 -or ($i -gt 0 -and $stops[$i - 1].자치구) -or ($i -lt $stops.Count - 1 -and $stops[$i + 1].자치구)
        if (-not $near) { continue }
        $result.Add([pscustomobject][ordered]@{
            호선 = "${line}호선"; 경로ID = $pathId; 순서 = $i + 1; 역 = $stops[$i].역; 영문역명 = $stops[$i].영문; 역코드 = $stops[$i].코드
            위도 = $stops[$i].위도; 경도 = $stops[$i].경도; 자치구 = $(if ($stops[$i].자치구) { $stops[$i].자치구 } else { '서울 밖' })
        })
    }
}

# 다음 역 좌표 (Tableau에서 MAKELINE으로 역과 역 사이 선을 그릴 때 사용)
for ($i = 0; $i -lt $result.Count; $i++) {
    $nx = if ($i -lt $result.Count - 1 -and $result[$i + 1].경로ID -eq $result[$i].경로ID -and $result[$i + 1].순서 -eq $result[$i].순서 + 1) { $result[$i + 1] }
    $result[$i] | Add-Member 다음역 $(if ($nx) { $nx.역 } else { '' })
    $result[$i] | Add-Member 다음역_위도 $(if ($nx) { $nx.위도 } else { '' })
    $result[$i] | Add-Member 다음역_경도 $(if ($nx) { $nx.경도 } else { '' })
}

$result | Export-Csv (Join-Path $Out '지하철_1~9호선.csv') -NoTypeInformation -Encoding UTF8
"지하철_1~9호선.csv: $($result.Count) 행, 역 $(@($result | Select-Object -ExpandProperty 역 -Unique).Count) 개"
if ($missing) { "찾지 못한 역:"; $missing }
