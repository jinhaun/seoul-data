# 연휴 효과 표: 나라의 연휴(공휴일·명절, 방학 제외) 하나 = 한 줄. 연휴 기간의 서울 하루 평균 외국인을 직전 2주와 비교합니다.
#   발표_연휴효과 : 국적, 연휴명, 표시명(연휴명 (국적)), 시작일, 종료일, 일수, 연휴_하루평균, 직전2주_하루평균, 증가율
#   - 이어진 연휴 날짜는 하나로 묶고, 이름은 그 기간에 가장 많이 나온 연휴명(방학 제외)
#   - 직전2주 = 시작일 전 14일 중 공휴일·명절이 아닌 날 (주말·방학 포함). 직전 데이터가 없는 연휴(1월 1일 등)는 뺌
#   - 인원 데이터는 2026-10-18까지라 그 뒤 연휴는 없음
# 먼저: make_nationality_csv.ps1 (국적별_일별), make_holiday_data.ps1 (연휴_달력)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Out  = Join-Path $Root '발표용_데이터\csv'
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$Inv  = [Globalization.CultureInfo]::InvariantCulture
$nats = @('중국', '미국', '일본', '태국')

$cal = @{}
foreach ($c in (Import-Csv (Join-Path $Root '연휴_데이터\csv\연휴_달력.csv') -Encoding UTF8)) { $cal["$($c.'날짜')|$($c.'국적')"] = $c }

$rows = foreach ($d in (Import-Csv (Join-Path $Root '국적별_분석\국적별_일별.csv') -Encoding UTF8)) {
    if ($nats -notcontains $d.'국적') { continue }
    $c = $cal["$($d.'날짜')|$($d.'국적')"]
    [pscustomobject]@{
        국적 = $d.'국적'; 날짜 = [datetime]::ParseExact($d.'날짜', 'yyyy-MM-dd', $Inv); 인원 = [double]::Parse($d.'하루평균인원', $Inv)
        연휴 = [bool]($c -and $c.'종류' -match '공휴일|명절'); 연휴명 = if ($c) { $c.'연휴명' } else { '' }
    }
}

$result = foreach ($n in $nats) {
    $r = @($rows | Where-Object { $_.'국적' -eq $n } | Sort-Object '날짜')
    # 하루 이하 간격으로 이어진 연휴 날짜를 한 묶음으로
    $groups = @(); $cur = @()
    foreach ($x in $r) {
        if (-not $x.'연휴') { continue }
        if ($cur.Count -and ($x.'날짜' - $cur[-1].'날짜').Days -gt 1) { $groups += , $cur; $cur = @() }
        $cur += $x
    }
    if ($cur.Count) { $groups += , $cur }

    foreach ($g in $groups) {
        $s = $g[0].'날짜'; $e = $g[-1].'날짜'
        $before = @($r | Where-Object { $_.'날짜' -lt $s -and $_.'날짜' -ge $s.AddDays(-14) -and -not $_.'연휴' })
        if (-not $before.Count) { continue }
        $name = ($g | ForEach-Object { $_.'연휴명' -split ' / ' } | Where-Object { $_ -and $_ -notmatch '방학' } |
                 Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name
        $a = ($g | Measure-Object '인원' -Average).Average
        $b = ($before | Measure-Object '인원' -Average).Average
        [pscustomobject]@{
            '국적' = $n; '연휴명' = $name; '표시명' = "$name ($n)"
            '시작일' = $s.ToString('yyyy-MM-dd'); '종료일' = $e.ToString('yyyy-MM-dd'); '일수' = $g.Count
            '연휴_하루평균' = [math]::Round($a, 1).ToString($Inv); '직전2주_하루평균' = [math]::Round($b, 1).ToString($Inv)
            '증가율' = [math]::Round($a / $b - 1, 4).ToString($Inv)
        }
    }
}

$path = Join-Path $Out '발표_연휴효과.csv'
$result | Export-Csv $path -Encoding UTF8 -NoTypeInformation
"발표_연휴효과: $(@($result).Count)줄 -> $path"
