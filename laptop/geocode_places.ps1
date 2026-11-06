# visitseoul 외국인용 관광지(명소·쇼핑·음식점, 한국어판)에 좌표를 붙여 태블로_외국인분석\관광지_목록.csv 로 저장합니다.
# 좌표를 찾는 순서
#   1) 이미 있는 장소_좌표.csv (서울시 실시간 도시데이터의 주요 장소 좌표)에 같은 이름이 있으면 그 값
#   2) 장소 이름으로 검색한 값 (주소 검색 결과와 3km 넘게 다르면 주소 쪽을 믿음)
#   3) 도로명주소 → 지번주소 → 도로명주소(건물번호까지) 로 검색한 값
# 검색은 OpenStreetMap Nominatim(무료, 키 불필요)을 쓰고, 사용 규칙상 1초에 1건만 요청합니다.
# 받은 좌표는 관광지_좌표_캐시_v2.csv 에 저장해 두므로, 다시 실행하면 새 장소만 찾습니다.
# 사용: powershell -File geocode_places.ps1
#       powershell -File geocode_places.ps1 -Kinds 명소 -CacheOnly   (이미 받은 좌표만으로 빠르게 만들기)

param([string[]]$Kinds = @('명소', '쇼핑', '음식점'), [switch]$CacheOnly)

$ErrorActionPreference = 'Stop'
$Root  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Out   = Join-Path $Root '태블로_외국인분석'
$Cache = Join-Path $Root '외국인_공공데이터\관광지_좌표_캐시_v2.csv'
$Utf8  = New-Object System.Text.UTF8Encoding($false)

$coordCache = @{}
if (Test-Path $Cache) { Import-Csv $Cache -Encoding UTF8 | ForEach-Object { $coordCache[$_.검색어] = $_ } }

$wc = New-Object System.Net.WebClient
function Geocode([string]$q) {
    if (-not $q) { return $null }
    if ($coordCache.ContainsKey($q)) { $c = $coordCache[$q]; if ($c.위도) { return $c } else { return $null } }
    if ($CacheOnly) { return $null }
    Start-Sleep -Milliseconds 1100
    $wc.Headers['User-Agent'] = 'seoul-tableau-portfolio/1.0 (personal study)'
    $j = $null
    try { $j = $Utf8.GetString($wc.DownloadData('https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=kr&viewbox=126.76,37.71,127.19,37.42&bounded=1&q=' + [uri]::EscapeDataString($q))) | ConvertFrom-Json } catch { }
    $hit = [pscustomobject]@{ 검색어 = $q; 위도 = $(if ($j) { $j[0].lat } else { '' }); 경도 = $(if ($j) { $j[0].lon } else { '' }); 종류 = $(if ($j) { $j[0].class } else { '' }) }
    $coordCache[$q] = $hit
    $hit | Export-Csv $Cache -NoTypeInformation -Encoding UTF8 -Append
    if ($hit.위도) { $hit } else { $null }
}
function Meters($a, $b) {
    $la1 = [double]$a.위도 * [math]::PI / 180; $la2 = [double]$b.위도 * [math]::PI / 180
    $dLa = $la2 - $la1; $dLo = ([double]$b.경도 - [double]$a.경도) * [math]::PI / 180
    $h = [math]::Pow([math]::Sin($dLa / 2), 2) + [math]::Cos($la1) * [math]::Cos($la2) * [math]::Pow([math]::Sin($dLo / 2), 2)
    2 * 6371000 * [math]::Asin([math]::Sqrt($h))
}
function Get-Gu($addr) { if ($addr -match '서울(?:특별시|시)?\s+(\S+구)') { $Matches[1] } }
function Road($a) { ($a -replace '^\d{5}\s+', '' -replace '\s*\(.*$', '').Trim() }      # 우편번호, 괄호 뒤 상세주소 제거
function Jibun($a) { ($a -replace '^\d{3}-\d{3}\s+', '' -replace '^(.*?\S+[동가리]\s+(산\s*)?\d+(-\d+)?).*$', '$1').Trim() }   # 번지까지만
function RoadShort($a) { $s = (Road $a) -replace '\s지하\s', ' '; if ($s -match '^(.*?\S+(로|길)\s*\d+(-\d+)?)') { $Matches[1] } }   # '지하'·건물명 빼고 건물번호까지
function CleanName($n) { ($n -replace '[\(（].*?[\)）]', '' -replace '^\d{4}\s+', '').Trim() }   # 괄호, '1898 명동성당' 같은 앞 연도 제거
function Key($n) { (CleanName $n) -replace '[\s·・]', '' }

# 1) 이미 있는 좌표 (서울시 실시간 도시데이터 장소 목록)
$known = @{}
Import-Csv (Join-Path $Root '장소_좌표.csv') -Encoding UTF8 | ForEach-Object { $known[(Key $_.장소)] = [pscustomobject]@{ 위도 = $_.위도; 경도 = $_.경도 } }

$rows = New-Object System.Collections.Generic.List[object]
foreach ($kind in $Kinds) {
    $list = @(Import-Csv (Join-Path $Root "외국인_공공데이터\관광_${kind}_5개언어.csv") -Encoding UTF8 | Where-Object LANG_CODE_ID -eq 'ko')
    $n = 0
    foreach ($r in $list) {
        $n++; if ($n % 100 -eq 0) { "$kind $n / $($list.Count)" }
        if ($kind -eq '명소' -and $r.POST_SJ -match '짐\s*보관|물품\s*보관|보관소|락커|창고|러기지|스토리지|Luggage') { continue }
        $gu = Get-Gu $r.ADDRESS; if (-not $gu) { $gu = Get-Gu $r.NEW_ADDRESS }
        if (-not $gu) { continue }   # 서울 밖(인천공항 등)·주소 없음

        $g = $null; $src = ''
        if ($known[(Key $r.POST_SJ)]) { $g = $known[(Key $r.POST_SJ)]; $src = '서울시 장소좌표' }
        else {
            $ga = $null; $asrc = ''
            foreach ($t in @(@('도로명주소', (Road $r.NEW_ADDRESS)), @('지번주소', (Jibun $r.ADDRESS)), @('도로명주소(건물번호까지)', (RoadShort $r.NEW_ADDRESS)))) {
                $ga = Geocode $t[1]; if ($ga) { $asrc = $t[0]; break }
            }
            $gn = Geocode "$(CleanName $r.POST_SJ), $gu"
            if ($gn -and (-not $ga -or (Meters $gn $ga) -le 3000)) { $g = $gn; $src = '장소이름' }
            elseif ($ga) { $g = $ga; $src = $(if ($ga.종류 -eq 'highway') { "$asrc(도로 위치, 대략)" } else { $asrc }) }
        }
        $rows.Add([pscustomobject][ordered]@{
            종류 = $kind; 관광지 = $r.POST_SJ; 자치구 = $gu
            주소 = (Road $r.NEW_ADDRESS); 위도 = $(if ($g) { $g.위도 } else { '' }); 경도 = $(if ($g) { $g.경도 } else { '' }); 좌표출처 = $src
            가까운_지하철 = $r.SUBWAY_INFO; 운영시간 = $r.CMMN_USE_TIME; 운영요일 = $r.CMMN_BSNDE; 휴무일 = $r.CMMN_RSTDE
            전화 = $r.CMMN_TELNO; 홈페이지 = $r.CMMN_HMPG_URL; 태그 = $r.TAG; 소개페이지 = $r.POST_URL
        })
    }
}
$wc.Dispose()

$rows | Export-Csv (Join-Path $Out '관광지_목록.csv') -NoTypeInformation -Encoding UTF8
$miss = @($rows | Where-Object { -not $_.위도 }).Count
"관광지_목록.csv: $($rows.Count) 곳 (좌표 못 찾음 $miss 곳)"
$rows | Group-Object 좌표출처 | ForEach-Object { "  $(if ($_.Name) { $_.Name } else { '못 찾음' }): $($_.Count)" }
