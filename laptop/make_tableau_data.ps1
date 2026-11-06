# Tableau 외국인 분석용 데이터를 태블로_외국인분석 폴더에 만듭니다.
# 사용: powershell -File make_tableau_data.ps1
# 새 데이터가 쌓이면 make_tourism_csv.ps1 로 합본을 갱신한 뒤 이 스크립트를 다시 실행하세요.

$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Out     = Join-Path $Root '태블로_외국인분석'
$Utf8Bom = New-Object System.Text.UTF8Encoding($true)
New-Item -ItemType Directory -Force -Path $Out | Out-Null

. (Join-Path $Root 'tableau_settings.ps1')   # 국적, 공휴일, 시간구간 설정

# ---------- 1. 외국인_시간대.csv ----------
$src = Join-Path $Root '외국인_관광\합본\외국인생활인구_단기_전체.csv'
$reader = New-Object System.IO.StreamReader($src, [System.Text.Encoding]::UTF8)
$header = Split-CsvLine $reader.ReadLine()
$idx = @{}; for ($i = 0; $i -lt $header.Count; $i++) { $idx[$header[$i]] = $i }
$countryCols = $header[7..($header.Count - 1)]

$writer = New-Object System.IO.StreamWriter((Join-Path $Out '외국인_시간대.csv'), $false, $Utf8Bom)
$writer.WriteLine('일시,날짜,월,요일,날짜유형,공휴일명,시간,시간구간,자치구코드,자치구,국적,인구')
$guCodes = @{}
$dates = @{}
$rows = 0
while ($null -ne ($line = $reader.ReadLine())) {
    $v = Split-CsvLine $line
    if ($v.Count -ne $header.Count) { throw "열 개수가 맞지 않는 줄: $line" }
    $date = $v[$idx['날짜']]; $dow = $v[$idx['요일']]; $h = [int]$v[$idx['시간']]
    $code = $v[$idx['자치구코드']]; $gu = $v[$idx['자치구']]
    $guCodes[$gu] = $code; $dates[$date] = $true

    $hol = $Holidays[$date]
    $dayType = DayType $date $dow

    $sum = @{}
    foreach ($c in $countryCols) {
        $num = if ($v[$idx[$c]]) { [double]$v[$idx[$c]] } else { 0 }
        $k = if ($TopCountries -contains $c) { $c } else { '기타' }
        $sum[$k] += $num
    }
    $prefix = '{0} {1:00}:00:00,{0},{2},{3},{4},{5},{6},{7},{8},{9}' -f $date, $h, ([int]$date.Substring(5, 2)), $dow, $dayType, $hol, $h, (TimeBucket $h), $code, $gu
    foreach ($k in ($TopCountries + '기타')) {
        $writer.WriteLine(('{0},{1},{2}' -f $prefix, $k, [math]::Round($sum[$k], 2)))
        $rows++
    }
}
$reader.Close(); $writer.Close()
$dateList = $dates.Keys | Sort-Object
"외국인_시간대.csv: $rows 행 ($($dateList[0]) ~ $($dateList[-1]), $($dateList.Count)일)"

# ---------- 2. 자치구_정보.csv ----------
$info = [ordered]@{}
foreach ($gu in ($guCodes.Keys | Sort-Object)) {
    $info[$gu] = [ordered]@{ 자치구코드=$guCodes[$gu]; 자치구=$gu; 명소_수=0; 쇼핑_수=0; 음식점_수=0; 관광장소_합계=0
                             호텔_수=0; 호텔_객실수=0; 외국인민박_수=0; 외국인민박_객실수=0; 숙박_합계=0; 관광특구_수=0 }
}

function Get-Gu($addr) { if ($addr -match '서울(?:특별시|시)?\s+(\S+구)') { $Matches[1] } }

foreach ($kind in '명소','쇼핑','음식점') {
    $f = Join-Path $Root "외국인_공공데이터\관광_${kind}_5개언어.csv"
    $skipped = 0
    foreach ($r in (Import-Csv $f -Encoding UTF8 | Where-Object LANG_CODE_ID -eq 'ko')) {
        if ($kind -eq '명소' -and $r.POST_SJ -match '짐\s*보관|물품\s*보관|보관소|락커') { $skipped++; continue }
        $gu = Get-Gu $r.ADDRESS; if (-not $gu) { $gu = Get-Gu $r.NEW_ADDRESS }
        if ($gu -and $info.Contains($gu)) { $info[$gu]["${kind}_수"]++ } else { $skipped++ }
    }
    "관광 ${kind}: 구를 못 찾았거나 제외한 곳 $skipped 개"
}

foreach ($pair in @(@('호텔','숙박_호텔_최신.csv'), @('외국인민박','숙박_외국인민박_최신.csv'))) {
    $kind = $pair[0]
    foreach ($r in (Import-Csv (Join-Path $Root "외국인_관광\합본\$($pair[1])") -Encoding UTF8 | Where-Object 영업상태 -eq '영업/정상')) {
        if (-not $info.Contains($r.자치구)) { continue }
        $info[$r.자치구]["${kind}_수"]++
        if ($r.객실수) { $info[$r.자치구]["${kind}_객실수"] += [int][double]$r.객실수 }
    }
}

# ---------- 3. 관광특구.csv ----------
$zoneNames = @{ '강남 MICE 관광특구'='강남마이스 관광특구'; '동대문 관광특구'='동대문패션타운 관광특구'; '명동 관광특구'='명동남대문북창동다동무교동 관광특구'
                '이태원 관광특구'='이태원관광특구'; '잠실 관광특구'='잠실관광특구'; '종로·청계 관광특구'='종로청계 관광특구'; '홍대 관광특구'='홍대 문화예술 관광특구' }
$zoneInfo = @{}; Import-Csv (Join-Path $Root '외국인_공공데이터\관광특구_한국어.csv') -Encoding UTF8 | ForEach-Object { $zoneInfo[$_.관광특구명] = $_ }
$zones = Import-Csv (Join-Path $Root '장소_좌표.csv') -Encoding UTF8 | Where-Object 분류 -eq '관광특구' | ForEach-Object {
    $z = $zoneInfo[$zoneNames[$_.장소]]
    $info[$_.자치구].관광특구_수++
    [pscustomobject][ordered]@{ 관광특구=$_.장소; 정식명칭=$z.관광특구명; 영문명=$z.영문명; 자치구=$_.자치구; 행정동=$z.행정동; 지정일=$z.지정일; 면적_km2=$z.면적_제곱킬로미터; 위도=$_.위도; 경도=$_.경도 }
}
$zones | Export-Csv (Join-Path $Out '관광특구.csv') -NoTypeInformation -Encoding UTF8
"관광특구.csv: $(@($zones).Count) 곳"

foreach ($g in $info.Values) {
    $g.관광장소_합계 = $g.명소_수 + $g.쇼핑_수 + $g.음식점_수
    $g.숙박_합계 = $g.호텔_수 + $g.외국인민박_수
}
$info.Values | ForEach-Object { [pscustomobject]$_ } | Export-Csv (Join-Path $Out '자치구_정보.csv') -NoTypeInformation -Encoding UTF8
"자치구_정보.csv: $($info.Count) 개 구"
