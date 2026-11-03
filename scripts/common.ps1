# 공통 함수 (GitHub Actions의 PowerShell 7과 Windows PowerShell 5.1 양쪽에서 동작)
# 다른 스크립트에서 . "$PSScriptRoot/common.ps1" 로 불러 씁니다.

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Utf8     = New-Object System.Text.UTF8Encoding($false)
$Utf8Bom  = New-Object System.Text.UTF8Encoding($true)
$KoCulture = [Globalization.CultureInfo]::GetCultureInfo('ko-KR')
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# 한국 시간
function Get-KstNow {
    foreach ($id in 'Asia/Seoul', 'Korea Standard Time') {
        try { return [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, $id) } catch {}
    }
    return [DateTime]::UtcNow.AddHours(9)
}

function Get-WeekdayKo([datetime]$d) { return $d.ToString('ddd', $KoCulture) }

# 서울시 인증키: GitHub Actions 비밀값(SEOUL_API_KEY) → 없으면 노트북의 config.txt (로컬 테스트용)
function Get-ApiKey {
    if ($env:SEOUL_API_KEY) { return $env:SEOUL_API_KEY.Trim() }
    $cfg = 'C:\Users\Administrator\Desktop\프로젝트\config.txt'
    if (Test-Path $cfg) {
        $k = Get-Content $cfg -Encoding UTF8 | ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') -and -not $_.Contains('=') } | Select-Object -First 1
        if ($k) { return $k }
    }
    throw 'SEOUL_API_KEY 가 없습니다.'
}

# 웹에서 글자 받기 (실패하면 최대 3번 재시도)
function Get-Text([string]$url, [string]$referer) {
    for ($try = 1; ; $try++) {
        $wc = New-Object System.Net.WebClient
        try {
            if ($referer) { $wc.Headers.Add('Referer', $referer) }
            $wc.Headers.Add('User-Agent', 'seoul-data-collector (github.com/jinhaun/seoul-data)')
            return $Utf8.GetString($wc.DownloadData($url))
        } catch {
            if ($try -ge 3) { throw }
            Start-Sleep -Seconds (5 * $try)
        } finally { $wc.Dispose() }
    }
}

function Get-Json([string]$url, [string]$referer) {
    for ($try = 1; ; $try++) {
        try { return (Get-Text $url $referer | ConvertFrom-Json) }
        catch { if ($try -ge 3) { throw }; Start-Sleep -Seconds (5 * $try) }
    }
}

# PowerShell 7은 JSON 안의 날짜 모양 글자를 날짜로 바꿔 버리므로 항상 글자로 되돌림
function To-Str($v, [string]$fmt = 'yyyy-MM-dd HH:mm') {
    if ($null -eq $v) { return '' }
    if ($v -is [datetime]) { return $v.ToString($fmt) }
    return ("$v").Trim()
}

# CSV 저장 (엑셀에서 한글이 안 깨지도록 BOM 포함)
function Write-CsvBom([string]$path, $rows) {
    $dir = Split-Path $path -Parent
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $lines = @($rows | ConvertTo-Csv -NoTypeInformation)
    [IO.File]::WriteAllLines($path, [string[]]$lines, $Utf8Bom)
}

# CSV 뒤에 줄 추가 (파일이 없으면 제목 줄과 함께 새로 만듦)
function Add-CsvRows([string]$path, $rows) {
    $rows = @($rows); if ($rows.Count -eq 0) { return }
    if (-not (Test-Path $path)) { Write-CsvBom $path $rows; return }
    $lines = @($rows | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1)
    [IO.File]::AppendAllLines($path, [string[]]$lines, $Utf8)
}

function Read-Csv([string]$path) {
    if (-not (Test-Path $path)) { return @() }
    return @(Import-Csv $path -Encoding UTF8)
}

# 실시간 도시데이터 장소 목록 (사이트에서 최신 목록, 실패하면 저장된 목록)
function Get-Hotspots {
    $meta = Join-Path $RepoRoot 'data/meta/장소_121곳.csv'
    try {
        $url = 'https://data.seoul.go.kr/SeoulRtd/api/hotspot-category?page=1&category=%EC%A0%84%EC%B2%B4%EB%B3%B4%EA%B8%B0&count=300'
        $res = Get-Json $url 'https://data.seoul.go.kr/SeoulRtd/list'
        $list = @($res.row | ForEach-Object {
            [pscustomobject][ordered]@{ '장소' = $_.area_nm; '분류' = $_.category; '위도' = $_.x; '경도' = $_.y }   # 이 목록은 x=위도, y=경도
        })
        if ($list.Count -ge 50) { Write-CsvBom $meta $list; return $list }
    } catch { Write-Host "장소 목록 갱신 실패, 저장된 목록 사용: $($_.Exception.Message)" }
    return Read-Csv $meta
}

# citydata 응답(장소 하나) -> 표 한 줄
function New-RealtimeRow($d, [string]$collected) {
    $p = $d.LIVE_PPLTN_STTS | Select-Object -First 1
    $w = $d.WEATHER_STTS | Select-Object -First 1
    $r = $d.ROAD_TRAFFIC_STTS.AVG_ROAD_DATA
    $c = $d.LIVE_CMRCL_STTS
    $sub = $d.LIVE_SUB_PPLTN; $bus = $d.LIVE_BUS_PPLTN
    return [pscustomobject][ordered]@{
        '수집시각' = $collected
        '인구기준시각' = (To-Str $p.PPLTN_TIME)
        '장소코드' = (To-Str $d.AREA_CD); '장소' = (To-Str $d.AREA_NM)
        '혼잡도' = (To-Str $p.AREA_CONGEST_LVL)
        '인구_최소' = (To-Str $p.AREA_PPLTN_MIN); '인구_최대' = (To-Str $p.AREA_PPLTN_MAX)
        '남성비율' = (To-Str $p.MALE_PPLTN_RATE); '여성비율' = (To-Str $p.FEMALE_PPLTN_RATE)
        '0~9세' = (To-Str $p.PPLTN_RATE_0); '10대' = (To-Str $p.PPLTN_RATE_10); '20대' = (To-Str $p.PPLTN_RATE_20)
        '30대' = (To-Str $p.PPLTN_RATE_30); '40대' = (To-Str $p.PPLTN_RATE_40); '50대' = (To-Str $p.PPLTN_RATE_50)
        '60대' = (To-Str $p.PPLTN_RATE_60); '70대이상' = (To-Str $p.PPLTN_RATE_70)
        '상주인구비율' = (To-Str $p.RESNT_PPLTN_RATE); '비상주인구비율' = (To-Str $p.NON_RESNT_PPLTN_RATE)
        '상권활성도' = (To-Str $c.AREA_CMRCL_LVL)
        '기온' = (To-Str $w.TEMP); '강수형태' = (To-Str $w.PRECPT_TYPE)
        '미세먼지' = (To-Str $w.PM10); '초미세먼지' = (To-Str $w.PM25)
        '도로소통' = (To-Str $r.ROAD_TRAFFIC_IDX); '도로평균속도' = (To-Str $r.ROAD_TRAFFIC_SPD)
        '지하철_오늘누적승차' = (To-Str $sub.SUB_ACML_GTON_PPLTN_MAX); '지하철_오늘누적하차' = (To-Str $sub.SUB_ACML_GTOFF_PPLTN_MAX)
        '버스_오늘누적승차' = (To-Str $bus.BUS_ACML_GTON_PPLTN_MAX); '버스_오늘누적하차' = (To-Str $bus.BUS_ACML_GTOFF_PPLTN_MAX)
    }
}

# 날짜 -> 저장 경로 조각 (2026-11/2026-11-03)
function Get-DayPath([datetime]$d) { return ($d.ToString('yyyy-MM') + '/' + $d.ToString('yyyy-MM-dd')) }

# 두 좌표 사이 거리(m)
function Get-DistanceM([double]$lat1, [double]$lng1, [double]$lat2, [double]$lng2) {
    $rad = [Math]::PI / 180
    $dLat = ($lat2 - $lat1) * $rad; $dLng = ($lng2 - $lng1) * $rad
    $a = [Math]::Sin($dLat / 2) * [Math]::Sin($dLat / 2) + [Math]::Cos($lat1 * $rad) * [Math]::Cos($lat2 * $rad) * [Math]::Sin($dLng / 2) * [Math]::Sin($dLng / 2)
    return 2 * 6371000.0 * [Math]::Atan2([Math]::Sqrt($a), [Math]::Sqrt(1 - $a))
}

function Get-NearestSpot([double]$lat, [double]$lng, $spots) {
    $best = $null; $bd = [double]::MaxValue
    foreach ($s in $spots) {
        $sl = 0.0; $sg = 0.0
        if (-not ([double]::TryParse("$($s.'위도')", [ref]$sl) -and [double]::TryParse("$($s.'경도')", [ref]$sg))) { continue }
        $dd = Get-DistanceM $lat $lng $sl $sg
        if ($dd -lt $bd) { $bd = $dd; $best = $s.'장소' }
    }
    if ($best) { return @($best, [int][Math]::Round($bd)) } else { return @('', '') }
}

# 중부원점 TM(EPSG:5174, Bessel) -> WGS84 위경도
function Convert-TmToWgs84([double]$x, [double]$y) {
    $a = 6377397.155; $f = 1 / 299.1528128
    $e2 = 2 * $f - $f * $f; $ep2 = $e2 / (1 - $e2); $e4 = $e2 * $e2; $e6 = $e4 * $e2
    $lat0 = 38 * [Math]::PI / 180; $lon0 = 127.0028902777778 * [Math]::PI / 180
    $arc = { param($p) $a * ((1 - $e2 / 4 - 3 * $e4 / 64 - 5 * $e6 / 256) * $p - (3 * $e2 / 8 + 3 * $e4 / 32 + 45 * $e6 / 1024) * [Math]::Sin(2 * $p) + (15 * $e4 / 256 + 45 * $e6 / 1024) * [Math]::Sin(4 * $p) - (35 * $e6 / 3072) * [Math]::Sin(6 * $p)) }
    $marc = (& $arc $lat0) + ($y - 500000.0)
    $mu = $marc / ($a * (1 - $e2 / 4 - 3 * $e4 / 64 - 5 * $e6 / 256))
    $e1 = (1 - [Math]::Sqrt(1 - $e2)) / (1 + [Math]::Sqrt(1 - $e2))
    $p1 = $mu + (3 * $e1 / 2 - 27 * [Math]::Pow($e1, 3) / 32) * [Math]::Sin(2 * $mu) + (21 * $e1 * $e1 / 16 - 55 * [Math]::Pow($e1, 4) / 32) * [Math]::Sin(4 * $mu) + (151 * [Math]::Pow($e1, 3) / 96) * [Math]::Sin(6 * $mu) + (1097 * [Math]::Pow($e1, 4) / 512) * [Math]::Sin(8 * $mu)
    # (PowerShell 변수 이름은 대소문자를 구분하지 않으므로 이름을 모두 다르게 씀)
    $s1 = [Math]::Sin($p1); $c1 = [Math]::Cos($p1); $tn1 = [Math]::Tan($p1)
    $cc = $ep2 * $c1 * $c1; $tt = $tn1 * $tn1
    $n1 = $a / [Math]::Sqrt(1 - $e2 * $s1 * $s1); $r1 = $a * (1 - $e2) / [Math]::Pow(1 - $e2 * $s1 * $s1, 1.5)
    $dd = ($x - 200000.0) / $n1
    $lat = $p1 - ($n1 * $tn1 / $r1) * ($dd * $dd / 2 - (5 + 3 * $tt + 10 * $cc - 4 * $cc * $cc - 9 * $ep2) * [Math]::Pow($dd, 4) / 24 + (61 + 90 * $tt + 298 * $cc + 45 * $tt * $tt - 252 * $ep2 - 3 * $cc * $cc) * [Math]::Pow($dd, 6) / 720)
    $lon = $lon0 + ($dd - (1 + 2 * $tt + $cc) * [Math]::Pow($dd, 3) / 6 + (5 - 2 * $cc + 28 * $tt - 3 * $cc * $cc + 8 * $ep2 + 24 * $tt * $tt) * [Math]::Pow($dd, 5) / 120) / $c1
    $nb = $a / [Math]::Sqrt(1 - $e2 * [Math]::Sin($lat) * [Math]::Sin($lat))
    $gx = $nb * [Math]::Cos($lat) * [Math]::Cos($lon); $gy = $nb * [Math]::Cos($lat) * [Math]::Sin($lon); $gz = $nb * (1 - $e2) * [Math]::Sin($lat)
    $sec = [Math]::PI / (180 * 3600); $rx = 1.16 * $sec; $ry = -2.31 * $sec; $rz = -1.63 * $sec; $sc = 1 + 6.43e-6
    $X2 = -115.80 + $sc * ($gx - $rz * $gy + $ry * $gz); $Y2 = 474.99 + $sc * ($rz * $gx + $gy - $rx * $gz); $Z2 = 674.11 + $sc * (-$ry * $gx + $rx * $gy + $gz)
    $aw = 6378137.0; $fw = 1 / 298.257223563; $e2w = 2 * $fw - $fw * $fw
    $lonW = [Math]::Atan2($Y2, $X2); $pw = [Math]::Sqrt($X2 * $X2 + $Y2 * $Y2); $latW = [Math]::Atan2($Z2, $pw * (1 - $e2w))
    for ($i = 0; $i -lt 5; $i++) { $nw = $aw / [Math]::Sqrt(1 - $e2w * [Math]::Sin($latW) * [Math]::Sin($latW)); $latW = [Math]::Atan2($Z2 + $e2w * $nw * [Math]::Sin($latW), $pw) }
    return @([Math]::Round($latW * 180 / [Math]::PI, 6), [Math]::Round($lonW * 180 / [Math]::PI, 6))
}

$GuNames = @{
    '11110'='종로구'; '11140'='중구'; '11170'='용산구'; '11200'='성동구'; '11215'='광진구'; '11230'='동대문구'; '11260'='중랑구'
    '11290'='성북구'; '11305'='강북구'; '11320'='도봉구'; '11350'='노원구'; '11380'='은평구'; '11410'='서대문구'; '11440'='마포구'
    '11470'='양천구'; '11500'='강서구'; '11530'='구로구'; '11545'='금천구'; '11560'='영등포구'; '11590'='동작구'; '11620'='관악구'
    '11650'='서초구'; '11680'='강남구'; '11710'='송파구'; '11740'='강동구'
}
$NatNames = [ordered]@{
    'SPOP'='생활인구합계'; 'CHN'='중국'; 'JPN'='일본'; 'USA'='미국'; 'THA'='태국'; 'VNM'='베트남'; 'PHL'='필리핀'; 'IDN'='인도네시아'
    'MNG'='몽골'; 'RUS'='러시아'; 'KAZ'='카자흐스탄'; 'UZB'='우즈베키스탄'; 'CAN'='캐나다'; 'FRA'='프랑스'; 'IND'='인도'; 'NPL'='네팔'
    'LKA'='스리랑카'; 'KHM'='캄보디아'; 'PAK'='파키스탄'; 'MMR'='미얀마'; 'BGD'='방글라데시'; 'ETC'='기타'
}
