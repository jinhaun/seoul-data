# 발표 흐름에 필요한 표만 골라 만듭니다. 결론 확인용으로 먼저 CSV(발표용_데이터\csv)만 만들고, -Excel 을 붙이면 엑셀 하나(발표용_데이터.xlsx)까지 만듭니다.
#   발표_자치구별_외국인 : 국적(전체+7개) x 자치구. 하루 평균 외국인, 그 국적 중 이 구 비중, 구청 위도·경도   → 차트 1·2
#   발표_월별_환율_기온   : 월 x 국적. 서울 하루 평균 외국인, 월평균 원화환율, 현지·서울 기온                  → 차트 3 (관계 없음)
#   발표_구별_시설        : 자치구 x 시설 종류 = 한 줄 (관광명소·호텔·외국인민박·일반숙박·쇼핑·성형외과·피부과)  → 차트 4
#   발표_중국인_구별      : 자치구. 단기 중국인(방문) vs 장기 중국인(거주) 하루 평균, 영업 중인 중국식 음식점 수 → 차트 5
#   발표_중국인_동별      : 행정동. 단기 중국인 하루 평균, 그 동 단기 외국인 중 중국인 비율, 동 중심 위도·경도 → 차트 5 지도
# 먼저: make_nationality_csv.ps1, make_hackathon_data.ps1, make_dong_csv.ps1, download_extra.ps1

param([switch]$Excel)   # 붙이면 발표용_데이터.xlsx 까지 만듦

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Dir  = Join-Path $Root '발표용_데이터'
$Out  = Join-Path $Dir 'csv'
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$Inv  = [Globalization.CultureInfo]::InvariantCulture
$nats = @('중국', '미국', '일본', '태국', '인도네시아', '프랑스', '캐나다')
$top4 = @('종로구', '중구', '마포구', '강남구')

$fac = @{}; foreach ($r in (Import-Csv (Join-Path $Root '해커톤_데이터\csv\자치구_시설.csv') -Encoding UTF8)) { $fac[$r.'자치구'] = $r }
$all = @{}  # 자치구 -> 전체 외국인 하루 평균
$guNat = @(Import-Csv (Join-Path $Root '국적별_분석\국적별_자치구별.csv') -Encoding UTF8)
foreach ($r in $guNat) { if ($r.'국적' -eq '전체') { $all[$r.'자치구'] = $r.'하루평균인원' } }

# 영업 중인 업소를 구별로 세기 ($match 가 있으면 상호에 그 글자가 든 곳만)
function Count-Gu($file, $match) {
    $cnt = @{}
    foreach ($r in (Import-Csv (Join-Path $Root "외국인_공공데이터\$file.csv") -Encoding UTF8)) {
        if ($r.TRDSTATENM -notlike '영업*') { continue }
        if ($match -and $r.BPLCNM -notlike "*$match*") { continue }
        $g = ((@($r.RDNWHLADDR, $r.SITEWHLADDR) | Where-Object { $_ } | Select-Object -First 1) -split ' ')[1]
        if ($g) { $cnt[$g] = [int]$cnt[$g] + 1 }
    }
    $cnt
}

# ---------- 1) 자치구별 외국인 ----------
$s1 = foreach ($r in ($guNat | Where-Object { $_.'국적' -in (@('전체') + $nats) })) {
    [pscustomobject][ordered]@{
        '국적' = $r.'국적'; '자치구' = $r.'자치구'
        '하루평균인원' = $r.'하루평균인원'; '국적내비중' = $r.'국적내비중'
        '상위4구' = $(if ($r.'자치구' -in $top4) { 'Y' } else { 'N' })
        '위도' = $fac[$r.'자치구'].'위도'; '경도' = $fac[$r.'자치구'].'경도'
    }
}
$s1 | Export-Csv (Join-Path $Out '발표_자치구별_외국인.csv') -NoTypeInformation -Encoding UTF8

# ---------- 2) 월별 환율·기온 ----------
$s2 = foreach ($r in (Import-Csv (Join-Path $Root '해커톤_데이터\csv\월별_방문_환율_기온.csv') -Encoding UTF8)) {
    [pscustomobject][ordered]@{
        '월' = $r.'월'; '국적' = $r.'국적'
        '하루평균인원' = $r.'하루평균인원'; '인원_1월대비_변화율' = $r.'인원_1월대비_변화율'
        '월평균_원화환율' = $r.'월평균_원화환율'; '단위' = $r.'단위'; '환율_1월대비_변화율' = $r.'환율_1월대비_변화율'
        '도시' = $r.'도시'; '현지기온' = $r.'현지_월평균기온'; '서울기온' = $r.'서울_월평균기온'; '서울보다_따뜻함' = $r.'서울보다_따뜻함'
    }
}
$s2 | Export-Csv (Join-Path $Out '발표_월별_환율_기온.csv') -NoTypeInformation -Encoding UTF8

# ---------- 3) 구별 시설 (길게: 시설 종류마다 한 줄) ----------
$hospital = @{}
foreach ($kw in '성형외과', '피부과') {
    $a = Count-Gu '업소_의원_인허가' $kw; $b = Count-Gu '업소_병원_인허가' $kw
    $c = @{}; foreach ($k in @($a.Keys) + @($b.Keys)) { $c[$k] = [int]$a[$k] + [int]$b[$k] }
    $hospital[$kw] = $c
}
$kinds = @(
    @('관광', '관광명소', { param($g) $fac[$g].'명소_수' }),
    @('숙박', '호텔', { param($g) $fac[$g].'호텔_수' }),
    @('숙박', '외국인민박', { param($g) $fac[$g].'외국인민박_수' }),
    @('숙박', '일반숙박(모텔 등)', { param($g) $fac[$g].'일반숙박_수' }),
    @('쇼핑', '쇼핑', { param($g) $fac[$g].'쇼핑_수' }),
    @('의료', '성형외과', { param($g) [int]$hospital['성형외과'][$g] }),
    @('의료', '피부과', { param($g) [int]$hospital['피부과'][$g] })
)
$s3 = foreach ($g in ($fac.Keys | Sort-Object)) {
    foreach ($k in $kinds) {
        [pscustomobject][ordered]@{
            '자치구' = $g; '상위4구' = $(if ($g -in $top4) { 'Y' } else { 'N' }); '외국인_하루평균' = $all[$g]
            '시설분류' = $k[0]; '시설종류' = $k[1]; '개수' = & $k[2] $g
        }
    }
}
$s3 | Export-Csv (Join-Path $Out '발표_구별_시설.csv') -NoTypeInformation -Encoding UTF8

# ---------- 4) 중국인 구별: 방문(단기) vs 거주(장기), 중국식 음식점 ----------
function Avg-Chinese($file) {
    $sum = @{}; $days = @{}; $hdr = $null
    foreach ($line in [IO.File]::ReadLines((Join-Path $Root "외국인_관광\합본\$file"), [Text.Encoding]::UTF8)) {
        $f = $line.Replace('"', '').Split(',')
        if (-not $hdr) { $hdr = $f; $iD = [array]::IndexOf($hdr, '날짜'); $iG = [array]::IndexOf($hdr, '자치구'); $iC = [array]::IndexOf($hdr, '중국'); $iT = [array]::IndexOf($hdr, '생활인구합계'); continue }
        $days[$f[$iD]] = 1
        if ($f[$iC]) { $sum["$($f[$iG])|중국"] = [double]$sum["$($f[$iG])|중국"] + [double]::Parse($f[$iC], $Inv) }
        if ($f[$iT]) { $sum["$($f[$iG])|전체"] = [double]$sum["$($f[$iG])|전체"] + [double]::Parse($f[$iT], $Inv) }
    }
    $res = @{}; foreach ($k in $sum.Keys) { $res[$k] = $sum[$k] / 24 / $days.Count }
    $res
}
$short = Avg-Chinese '외국인생활인구_단기_전체.csv'
$long  = Avg-Chinese '외국인생활인구_장기_전체.csv'
$cnRest = Count-Gu '업소_일반음식점_중국식' $null
$s4 = foreach ($g in ($fac.Keys | Sort-Object)) {
    [pscustomobject][ordered]@{
        '자치구' = $g
        '방문_중국인_하루평균' = [Math]::Round([double]$short["$g|중국"], 1)
        '방문외국인중_중국인비율' = $(if ($short["$g|전체"]) { [Math]::Round($short["$g|중국"] / $short["$g|전체"] * 100, 1) } else { '' })
        '거주_중국인_하루평균' = [Math]::Round([double]$long["$g|중국"], 1)
        '중국식음식점_수' = [int]$cnRest[$g]
        '위도' = $fac[$g].'위도'; '경도' = $fac[$g].'경도'
    }
}
$s4 | Export-Csv (Join-Path $Out '발표_중국인_구별.csv') -NoTypeInformation -Encoding UTF8

# ---------- 5) 중국인 동별 ----------
$s5 = foreach ($r in (Import-Csv (Join-Path $Root '동별_분석\동별_국적별_외국인.csv') -Encoding UTF8 | Where-Object { $_.'국적' -eq '중국' })) {
    [pscustomobject][ordered]@{
        '자치구' = $r.'자치구'; '행정동' = $r.'행정동'
        '방문_중국인_하루평균' = $r.'하루평균인원'; '동내_중국인비율' = $r.'동내_국적비율'
        '위도' = $r.'위도'; '경도' = $r.'경도'
    }
}
$s5 | Export-Csv (Join-Path $Out '발표_중국인_동별.csv') -NoTypeInformation -Encoding UTF8

"OK 1) $(@($s1).Count)줄 2) $(@($s2).Count)줄 3) $(@($s3).Count)줄 4) $(@($s4).Count)줄 5) $(@($s5).Count)줄 -> $Out"
# 엑셀은 결론이 확정된 뒤 -Excel 을 붙여 실행할 때만 만듦 (그 전에는 CSV로 숫자만 확인)
if ($Excel) {
    & (Join-Path $Root 'csv_to_xlsx.ps1') -Src $Out -Dst $Dir -Combine '발표용_데이터.xlsx' -Notes (Join-Path $Dir '읽어주세요.txt') `
        -Order '발표_자치구별_외국인', '발표_월별_환율_기온', '발표_구별_시설', '발표_중국인_구별', '발표_중국인_동별'
}
