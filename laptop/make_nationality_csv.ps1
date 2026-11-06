# 단기체류 외국인 생활인구(자치구 x 시간, 국적별)를 국적 기준으로 정리합니다.
# 원본: 외국인_관광\합본\외국인생활인구_단기_전체.csv  (먼저 make_tourism_csv.ps1 로 최신화)
# 결과: 국적별_분석\
#   국적별_일별.csv     : 날짜 x 국적, 서울 전체 하루 평균 인원 (요일·주말여부 포함)
#   국적별_월별.csv     : 월 x 국적, 하루 평균 인원 (평일/주말 따로)
#   국적별_자치구별.csv : 국적 x 자치구, 하루 평균 인원 (전체/평일/주말), 그 국적 안에서의 비중, 특화지수
#   국적별_자치구_월별.csv : 월 x 국적 x 자치구, 하루 평균 인원, 그 달 그 국적 안에서의 비중, 특화지수
# 주의: 생활인구는 "그 시간에 그 지역에 있던 사람 수"입니다. 하루 값 = 24시간 평균이며,
#       같은 사람이 여러 날 머물면 매일 잡히므로 "방문객 수(중복 없는 사람 수)"와는 다릅니다.

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Src  = Join-Path $Root '외국인_관광\합본\외국인생활인구_단기_전체.csv'
$Out  = Join-Path $Root '국적별_분석'
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$day   = @{}   # "날짜|국적" -> 합계(구 x 시간)
$gu    = @{}   # "국적|자치구|주말여부" -> 합계
$guM   = @{}   # "월|국적|자치구" -> 합계
$dayInfo = @{} # 날짜 -> @(요일, 주말여부)
$hdr = $null
foreach ($line in [IO.File]::ReadLines($Src, [Text.Encoding]::UTF8)) {
    $f = $line.Split(',') | ForEach-Object { $_.Trim('"') }
    if (-not $hdr) {
        $hdr = $f
        $iD = [array]::IndexOf($hdr, '날짜'); $iY = [array]::IndexOf($hdr, '요일'); $iW = [array]::IndexOf($hdr, '주말여부')
        $iG = [array]::IndexOf($hdr, '자치구'); $iS = [array]::IndexOf($hdr, '생활인구합계')
        $natIdx = @($iS) + @(($iS + 1)..($hdr.Count - 1))
        continue
    }
    $d = $f[$iD]; $w = $f[$iW]; $g = $f[$iG]
    if (-not $dayInfo[$d]) { $dayInfo[$d] = @($f[$iY], $w) }
    foreach ($i in $natIdx) {
        $v = $f[$i]; if (-not $v) { continue }          # 빈칸(인원이 적어 비공개) = 0 으로 봄
        $n = if ($i -eq $iS) { '전체' } else { $hdr[$i] }
        $x = [double]$v
        $k1 = "$d|$n"; $day[$k1] = [double]$day[$k1] + $x
        $k2 = "$n|$g|$w"; $gu[$k2] = [double]$gu[$k2] + $x
        $k3 = "$($d.Substring(0, 7))|$n|$g"; $guM[$k3] = [double]$guM[$k3] + $x
    }
}

$nats  = @('전체') + @($hdr[($iS + 1)..($hdr.Count - 1)])
$dates = @($dayInfo.Keys | Sort-Object)
$nWd = @($dates | Where-Object { $dayInfo[$_][1] -eq 'N' }).Count
$nWk = @($dates | Where-Object { $dayInfo[$_][1] -eq 'Y' }).Count

# 1) 날짜 x 국적
$daily = foreach ($d in $dates) {
    foreach ($n in $nats) {
        [pscustomobject][ordered]@{
            '날짜' = $d; '월' = $d.Substring(0, 7); '요일' = $dayInfo[$d][0]; '주말여부' = $dayInfo[$d][1]
            '국적' = $n; '하루평균인원' = [Math]::Round([double]$day["$d|$n"] / 24, 1)
        }
    }
}
$daily | Export-Csv (Join-Path $Out '국적별_일별.csv') -NoTypeInformation -Encoding UTF8

# 2) 월 x 국적 (평일/주말 나눠 하루 평균)
$monthly = $daily | Group-Object '월', '국적' | ForEach-Object {
    $g = $_.Group
    $wd = @($g | Where-Object { $_.'주말여부' -eq 'N' }); $wk = @($g | Where-Object { $_.'주말여부' -eq 'Y' })
    [pscustomobject][ordered]@{
        '월' = $g[0].'월'; '국적' = $g[0].'국적'
        '하루평균인원' = [Math]::Round((($g | Measure-Object '하루평균인원' -Average).Average), 1)
        '평일_하루평균' = $(if ($wd.Count) { [Math]::Round(($wd | Measure-Object '하루평균인원' -Average).Average, 1) } else { '' })
        '주말_하루평균' = $(if ($wk.Count) { [Math]::Round(($wk | Measure-Object '하루평균인원' -Average).Average, 1) } else { '' })
        '집계일수' = $g.Count
    }
}
$monthly | Export-Csv (Join-Path $Out '국적별_월별.csv') -NoTypeInformation -Encoding UTF8

# 3) 국적 x 자치구 (하루 평균 = 합계 / 24 / 일수), 비중, 특화지수
$guNames = @($gu.Keys | ForEach-Object { $_.Split('|')[1] } | Sort-Object -Unique)
$allAvg = @{}
foreach ($g in $guNames) { $allAvg[$g] = ([double]$gu["전체|$g|N"] + [double]$gu["전체|$g|Y"]) / 24 / ($nWd + $nWk) }
$allTotal = ($allAvg.Values | Measure-Object -Sum).Sum
$byGu = foreach ($n in $nats) {
    $avg = @{}
    foreach ($g in $guNames) { $avg[$g] = ([double]$gu["$n|$g|N"] + [double]$gu["$n|$g|Y"]) / 24 / ($nWd + $nWk) }
    $tot = ($avg.Values | Measure-Object -Sum).Sum
    foreach ($g in $guNames) {
        $wdA = [double]$gu["$n|$g|N"] / 24 / $nWd
        $wkA = [double]$gu["$n|$g|Y"] / 24 / $nWk
        $share = if ($tot) { $avg[$g] / $tot * 100 } else { 0 }
        $base  = if ($allTotal) { $allAvg[$g] / $allTotal * 100 } else { 0 }
        [pscustomobject][ordered]@{
            '국적' = $n; '자치구' = $g
            '하루평균인원' = [Math]::Round($avg[$g], 1)
            '평일_하루평균' = [Math]::Round($wdA, 1); '주말_하루평균' = [Math]::Round($wkA, 1)
            '주말증감률' = $(if ($wdA) { [Math]::Round(($wkA / $wdA - 1) * 100, 1) } else { '' })
            '국적내비중' = [Math]::Round($share, 2)
            '특화지수' = $(if ($base) { [Math]::Round($share / $base, 2) } else { '' })   # 1보다 크면 그 국적이 다른 외국인보다 이 구에 더 몰림
        }
    }
}
$byGu | Export-Csv (Join-Path $Out '국적별_자치구별.csv') -NoTypeInformation -Encoding UTF8

# 4) 월 x 국적 x 자치구 (하루 평균 = 합계 / 24 / 그 달 일수), 그 달의 비중, 특화지수
$months = @($dates | ForEach-Object { $_.Substring(0, 7) } | Sort-Object -Unique)
$byGuM = foreach ($m in $months) {
    $nDays = @($dates | Where-Object { $_.StartsWith($m) }).Count
    $allM = @{}
    foreach ($g in $guNames) { $allM[$g] = [double]$guM["$m|전체|$g"] / 24 / $nDays }
    $allMTotal = ($allM.Values | Measure-Object -Sum).Sum
    foreach ($n in $nats) {
        $avg = @{}
        foreach ($g in $guNames) { $avg[$g] = [double]$guM["$m|$n|$g"] / 24 / $nDays }
        $tot = ($avg.Values | Measure-Object -Sum).Sum
        foreach ($g in $guNames) {
            $share = if ($tot) { $avg[$g] / $tot * 100 } else { 0 }
            $base  = if ($allMTotal) { $allM[$g] / $allMTotal * 100 } else { 0 }
            [pscustomobject][ordered]@{
                '월' = $m; '국적' = $n; '자치구' = $g
                '하루평균인원' = [Math]::Round($avg[$g], 1)
                '국적내비중' = [Math]::Round($share, 2)
                '특화지수' = $(if ($base) { [Math]::Round($share / $base, 2) } else { '' })
                '집계일수' = $nDays
            }
        }
    }
}
$byGuM | Export-Csv (Join-Path $Out '국적별_자치구_월별.csv') -NoTypeInformation -Encoding UTF8

$readme = @(
    "국적별 단기체류 외국인 정리 (만든 시각: $((Get-Date).ToString('yyyy-MM-dd HH:mm')))",
    "원본: 외국인_관광\합본\외국인생활인구_단기_전체.csv ($($dates[0]) ~ $($dates[-1]), 평일 $nWd 일 / 주말 $nWk 일)",
    '',
    '값의 뜻: 하루평균인원 = 그날 24시간 동안 서울(또는 그 구)에 있던 단기체류 외국인 수의 평균.',
    '  같은 관광객이 3일 머물면 3일 모두 잡히므로 "중복 없는 방문객 수"가 아닙니다. 국가·지역·날짜끼리 비교하는 용도로 쓰세요.',
    '  여러 날을 합칠 때는 더하지 말고 평균을 내세요.',
    '특화지수: (그 국적 중 이 구에 있는 비율) / (전체 외국인 중 이 구에 있는 비율). 1.5면 그 국적이 평균보다 1.5배 이 구에 몰린다는 뜻.',
    '국적별_자치구_월별.csv: 위 값을 달마다 따로 계산한 것. 마지막 달은 원본이 끝난 날까지만 들어 있습니다(집계일수 참고).',
    '주말여부: 토·일 = Y. 공휴일은 평일(N)로 들어가 있습니다.',
    '원본에서 인원이 적어 비공개(*)인 칸은 0으로 계산했습니다.'
)
[IO.File]::WriteAllLines((Join-Path $Out '읽어주세요.txt'), $readme, (New-Object Text.UTF8Encoding($true)))
"OK 날짜 $($dates.Count)일, 국적 $($nats.Count - 1)개 + 전체, 자치구 $($guNames.Count)개"
