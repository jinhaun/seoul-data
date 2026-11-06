# 국적 x 시설 상관표: 25개 자치구에서 "그 국적 사람의 구별 비중(국적내비중)"과 "구별 시설 수"가 얼마나 같이 움직이는지(피어슨 상관계수).
#   발표_국적시설_상관 : 국적(전체+7) x 시설종류(7) = 한 줄. 국적, 시설분류, 시설종류, 상관계수, 강도(강함 0.7 이상 / 보통 0.4~0.7 / 약함 0.4 미만)
#   1에 가까울수록 시설이 많은 구에 그 나라 사람도 많음. 구가 25개뿐이고 인과관계는 아님.
#   한 국적 x 시설종류마다 그 국적이 많이 머무는 상위 4개 구가 한 줄씩(구_순위 1~4, 자치구). 상관계수·강도는 4줄 모두 같은 값.
#   서울평균대비_배 = 그 줄 자치구의 시설 수(개수) / 서울_구당평균(25개 구 평균). 1보다 크면 서울 평균보다 많음.
#   ※ 한 국적·시설에 4줄이라, 구 하나만 볼 때는 구_순위 필터(예: 1)를 거세요. 최다구·최다구_시설수 = 구_순위 1의 값(예전 열 유지)
# 먼저: make_presentation_data.ps1 (발표_자치구별_외국인, 발표_구별_시설)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Out  = Join-Path $Root '발표용_데이터\csv'
$Inv  = [Globalization.CultureInfo]::InvariantCulture

$visit = @{}   # "국적|자치구" -> 국적내비중
$people = @{}  # "국적|자치구" -> 하루평균인원
foreach ($r in (Import-Csv (Join-Path $Out '발표_자치구별_외국인.csv') -Encoding UTF8)) {
    $visit["$($r.'국적')|$($r.'자치구')"] = [double]::Parse($r.'국적내비중', $Inv)
    $people["$($r.'국적')|$($r.'자치구')"] = [double]::Parse($r.'하루평균인원', $Inv)
}
$topGus = @{}  # 국적 -> 하루 평균 인원이 많은 순 상위 4개 구
foreach ($n in ($people.Keys | ForEach-Object { ($_ -split '\|')[0] } | Select-Object -Unique)) {
    $topGus[$n] = @($people.Keys | Where-Object { $_ -like "$n|*" } | Sort-Object { $people[$_] } -Descending | Select-Object -First 4 | ForEach-Object { ($_ -split '\|')[1] })
}
$fac = @(Import-Csv (Join-Path $Out '발표_구별_시설.csv') -Encoding UTF8)
$gus   = @($fac | ForEach-Object { $_.'자치구' } | Select-Object -Unique)
$kinds = @($fac | Select-Object '시설분류', '시설종류' -Unique)
$nats  = @($visit.Keys | ForEach-Object { ($_ -split '\|')[0] } | Select-Object -Unique)

function Get-Corr([double[]]$x, [double[]]$y) {
    $mx = ($x | Measure-Object -Average).Average; $my = ($y | Measure-Object -Average).Average
    $sxy = 0; $sx = 0; $sy = 0
    for ($i = 0; $i -lt $x.Count; $i++) { $dx = $x[$i] - $mx; $dy = $y[$i] - $my; $sxy += $dx * $dy; $sx += $dx * $dx; $sy += $dy * $dy }
    $sxy / [math]::Sqrt($sx * $sy)
}

$result = foreach ($n in $nats) {
    $share = foreach ($g in $gus) { $visit["$n|$g"] }
    foreach ($k in $kinds) {
        $cnt = foreach ($g in $gus) { [double]($fac | Where-Object { $_.'시설종류' -eq $k.'시설종류' -and $_.'자치구' -eq $g }).'개수' }
        $c = Get-Corr $share $cnt
        $avg = ($cnt | Measure-Object -Average).Average
        $first = $topGus[$n][0]
        $firstCnt = [double]($fac | Where-Object { $_.'시설종류' -eq $k.'시설종류' -and $_.'자치구' -eq $first }).'개수'
        for ($i = 0; $i -lt $topGus[$n].Count; $i++) {
            $g = $topGus[$n][$i]
            $gc = [double]($fac | Where-Object { $_.'시설종류' -eq $k.'시설종류' -and $_.'자치구' -eq $g }).'개수'
            [pscustomobject][ordered]@{
                '국적' = $n; '시설분류' = $k.'시설분류'; '시설종류' = $k.'시설종류'
                '상관계수' = [math]::Round($c, 2).ToString($Inv)
                '강도' = $(if ($c -ge 0.7) { '강함' } elseif ($c -ge 0.4) { '보통' } else { '약함' })
                '최다구' = $first; '최다구_시설수' = $firstCnt
                '서울_구당평균' = [math]::Round($avg, 1).ToString($Inv)
                '서울평균대비_배' = [math]::Round($gc / $avg, 1).ToString($Inv)
                '구_순위' = $i + 1; '자치구' = $g; '개수' = $gc
                '국적_하루평균' = [math]::Round($people["$n|$g"], 0)
            }
        }
    }
}

$path = Join-Path $Out '발표_국적시설_상관.csv'
$result | Export-Csv $path -Encoding UTF8 -NoTypeInformation
"발표_국적시설_상관: $(@($result).Count)줄 -> $path"

# 발표_구별_시설배수 : 자치구(25) x 시설종류(7) = 한 줄. 그 구의 시설 수 / 서울 25개 구 평균 = 서울평균대비_배. 일본인 하루평균·순위도 붙임 (구 필터용)
$jp = @{}
foreach ($r in (Import-Csv (Join-Path $Out '발표_자치구별_외국인.csv') -Encoding UTF8)) { if ($r.'국적' -eq '일본') { $jp[$r.'자치구'] = [double]::Parse($r.'하루평균인원', $Inv) } }
$rank = @{}; $i = 0; foreach ($g in ($jp.Keys | Sort-Object { $jp[$_] } -Descending)) { $i++; $rank[$g] = $i }
$avgOf = @{}
foreach ($k in $kinds) { $avgOf[$k.'시설종류'] = ($fac | Where-Object { $_.'시설종류' -eq $k.'시설종류' } | ForEach-Object { [double]$_.'개수' } | Measure-Object -Average).Average }
$ratio = foreach ($r in $fac) {
    $avg = $avgOf[$r.'시설종류']
    [pscustomobject][ordered]@{
        '자치구' = $r.'자치구'; '시설분류' = $r.'시설분류'; '시설종류' = $r.'시설종류'; '개수' = [int]$r.'개수'
        '서울_구당평균' = [math]::Round($avg, 1).ToString($Inv)
        '서울평균대비_배' = [math]::Round([double]$r.'개수' / $avg, 1).ToString($Inv)
        '일본인_하루평균' = [math]::Round($jp[$r.'자치구'], 0); '일본인_순위' = $rank[$r.'자치구']
    }
}
$path2 = Join-Path $Out '발표_구별_시설배수.csv'
$ratio | Sort-Object '일본인_순위', '시설종류' | Export-Csv $path2 -Encoding UTF8 -NoTypeInformation
"발표_구별_시설배수: $(@($ratio).Count)줄 -> $path2"
