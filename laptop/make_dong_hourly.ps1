# 행정동 x 시간(0~23시) x 국적: 그 시간에 그 동에 있던 단기체류 외국인의 하루 평균 (5~10월 원본 전체 날짜 평균)
#   발표_동별_시간대 : 자치구, 행정동코드, 행정동, 을지로4가_주변(Y/N), 국적(전체+7), 시간, 하루평균인원, 평일_평균, 주말_평균, 위도, 경도
#   - 같은 사람이 여러 시간·여러 날 잡히므로 "그 시간에 그 동에 있던 인원"이지 중복 없는 방문객 수가 아님
#   - 비공개(*) 칸은 0. 공휴일은 평일로 셈 (주말 = 토·일)
#   - 을지로4가_주변 = 을지로4가역에서 걸어서 갈 만한 동 (을지로동·광희동·명동·필동·종로1·2·3·4가동·종로5·6가동·회현동·소공동)
# 먼저: make_dong_csv.ps1 (동별_분석\동별_국적별_외국인.csv 에서 동 이름·좌표를 가져옴)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Src  = Join-Path $Root '외국인_공공데이터\생활인구_행정동별_단기외국인'
$Out  = Join-Path $Root '발표용_데이터\csv'
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$Inv  = [Globalization.CultureInfo]::InvariantCulture

$nat  = [ordered]@{ SPOP = '전체'; CHN = '중국'; JPN = '일본'; USA = '미국'; THA = '태국'; IDN = '인도네시아'; FRA = '프랑스'; CAN = '캐나다' }
$near = @('을지로동', '광희동', '명동', '필동', '종로1·2·3·4가동', '종로5·6가동', '회현동', '소공동')

$dong = @{}   # 행정동코드 -> 이름·자치구·좌표
foreach ($r in (Import-Csv (Join-Path $Root '동별_분석\동별_국적별_외국인.csv') -Encoding UTF8)) {
    if ($r.'국적' -eq '전체') { $dong[$r.'행정동코드'] = $r }
}

$codes = @($nat.Keys)
$all = @{}; $wd = @{}; $we = @{}           # "동코드|시간" -> double[] (국적 순서)
$days = @{}; $wdDays = @{}; $weDays = @{}  # 날짜 모음 (평균을 낼 날 수)
foreach ($f in (Get-ChildItem $Src -Filter '*.csv' | Sort-Object Name)) {
    $rd = New-Object IO.StreamReader($f.FullName, [Text.Encoding]::UTF8)
    $h = $rd.ReadLine().Split(',') | ForEach-Object { $_.Trim('"') }
    $ix = foreach ($c in $codes) { [array]::IndexOf($h, $c) }
    $iY = [array]::IndexOf($h, 'YMD'); $iT = [array]::IndexOf($h, 'TT'); $iD = [array]::IndexOf($h, 'H_DNG_CD')
    while ($null -ne ($line = $rd.ReadLine())) {
        $v = $line.Split(',')
        $ymd = $v[$iY].Trim('"'); $key = "$($v[$iD].Trim('"'))|$([int]$v[$iT].Trim('"'))"
        if (-not $days.ContainsKey($ymd)) {
            $dow = [datetime]::ParseExact($ymd, 'yyyyMMdd', $Inv).DayOfWeek
            $days[$ymd] = ($dow -eq 'Saturday' -or $dow -eq 'Sunday')
            if ($days[$ymd]) { $weDays[$ymd] = 1 } else { $wdDays[$ymd] = 1 }
        }
        $bucket = if ($days[$ymd]) { $we } else { $wd }
        if (-not $all.ContainsKey($key)) { $all[$key] = New-Object double[] $codes.Count; $wd[$key] = New-Object double[] $codes.Count; $we[$key] = New-Object double[] $codes.Count }
        for ($i = 0; $i -lt $codes.Count; $i++) {
            $s = $v[$ix[$i]].Trim('"')
            if ($s -and $s -ne '*') { $x = [double]::Parse($s, $Inv); $all[$key][$i] += $x; $bucket[$key][$i] += $x }
        }
    }
    $rd.Close()
    "$($f.Name) 읽음"
}

$nAll = $days.Count; $nWd = $wdDays.Count; $nWe = $weDays.Count
$natNames = @($nat.Values)
$rows = foreach ($key in ($all.Keys | Sort-Object)) {
    $code, $hour = $key -split '\|'
    $d = $dong[$code]; if (-not $d) { continue }
    for ($i = 0; $i -lt $codes.Count; $i++) {
        [pscustomobject][ordered]@{
            '자치구' = $d.'자치구'; '행정동코드' = $code; '행정동' = $d.'행정동'
            '을지로4가_주변' = $(if ($near -contains $d.'행정동') { 'Y' } else { 'N' })
            '국적' = $natNames[$i]; '시간' = [int]$hour
            '하루평균인원' = [math]::Round($all[$key][$i] / $nAll, 1).ToString($Inv)
            '평일_평균' = [math]::Round($wd[$key][$i] / $nWd, 1).ToString($Inv)
            '주말_평균' = [math]::Round($we[$key][$i] / $nWe, 1).ToString($Inv)
            '위도' = $d.'위도'; '경도' = $d.'경도'
        }
    }
}

$path = Join-Path $Out '발표_동별_시간대.csv'
$rows | Export-Csv $path -Encoding UTF8 -NoTypeInformation
"발표_동별_시간대: $(@($rows).Count)줄 (날짜 $nAll 일 = 평일 $nWd + 주말 $nWe) -> $path"
