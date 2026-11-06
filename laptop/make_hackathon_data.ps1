# 해커톤용 데이터 네 묶음을 만듭니다. (먼저 make_nationality_csv.ps1 로 국적별_분석 을 최신화)
#   1) 자치구_국적별.csv : 자치구 x 국적 = 한 줄. 외국인 하루 평균 + 그 구의 숙박·관광지·쇼핑 수 + 구청 위도·경도
#      자치구_시설.csv   : 자치구 하나 = 한 줄. 숙박·관광지·쇼핑 수만
#   2) 연휴_목록.csv     : 나라별 2026년 공휴일·명절 연휴·방학 기간
#      연휴_효과.csv     : 연휴 하나 = 한 줄. 연휴 기간 하루 평균 외국인 vs 직전 4주 평균
#      일별_국적_연휴.csv : 날짜 x 국적 = 한 줄. 하루 평균 외국인 + 그날 그 나라 연휴 이름
#      연휴_자치구.csv   : 연휴 x 자치구 = 한 줄. 연휴 기간 vs 직전 4주를 구마다 + 그 구의 시설 수
#   3) 월별_방문_환율_기온.csv : 월 x 국적 = 한 줄. 하루 평균 외국인 + 환율 + 현지·서울 기온
#   4) 통합_csv\통합.csv : 하루 x 국적 x 자치구 = 한 줄. 인원·연휴·평소 대비 증가·환율·기온·그 구의 시설 (엑셀: 해커톤_통합.xlsx)
# 결과: 해커톤_데이터\csv\  (엑셀은 csv_to_xlsx.ps1 이 해커톤_데이터\ 에 만듦)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Out  = Join-Path $Root '해커톤_데이터\csv'
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$Inv  = [Globalization.CultureInfo]::InvariantCulture
$nats = @('중국', '미국', '일본', '태국', '인도네시아', '프랑스', '캐나다')

# ================= 1) 자치구 =================
# 구청 위치 (Tableau 지도에 점으로 찍기용)
$guPos = @{
    '종로구'=@(37.5735,126.9790); '중구'=@(37.5638,126.9976); '용산구'=@(37.5326,126.9905); '성동구'=@(37.5634,127.0369)
    '광진구'=@(37.5385,127.0823); '동대문구'=@(37.5744,127.0396); '중랑구'=@(37.6066,127.0927); '성북구'=@(37.5894,127.0167)
    '강북구'=@(37.6396,127.0257); '도봉구'=@(37.6688,127.0471); '노원구'=@(37.6543,127.0568); '은평구'=@(37.6027,126.9291)
    '서대문구'=@(37.5791,126.9368); '마포구'=@(37.5663,126.9019); '양천구'=@(37.5170,126.8664); '강서구'=@(37.5510,126.8495)
    '구로구'=@(37.4955,126.8875); '금천구'=@(37.4569,126.8955); '영등포구'=@(37.5264,126.8962); '동작구'=@(37.5124,126.9393)
    '관악구'=@(37.4784,126.9516); '서초구'=@(37.4837,127.0324); '강남구'=@(37.5172,127.0473); '송파구'=@(37.5145,127.1059)
    '강동구'=@(37.5301,127.1238)
}
# 영업 중인 업소를 구별로 세기 (자치구 열이 없으면 주소 두 번째 단어 = 구)
function Count-Gu($path, $guCol) {
    $cnt = @{}
    if (-not (Test-Path $path)) { return $cnt }
    foreach ($r in (Import-Csv $path -Encoding UTF8)) {
        if ("$($r.'영업상태')$($r.TRDSTATENM)" -notlike '영업*') { continue }
        $g = if ($guCol) { $r.$guCol } else { ((@($r.RDNWHLADDR, $r.SITEWHLADDR) | Where-Object { $_ } | Select-Object -First 1) -split ' ')[1] }
        if ($g) { $cnt[$g] = [int]$cnt[$g] + 1 }
    }
    $cnt
}
$motel = Count-Gu (Join-Path $Root '외국인_관광\합본\숙박_숙박업_최신.csv') '자치구'
$yuheung = Count-Gu (Join-Path $Root '외국인_공공데이터\업소_유흥주점_인허가.csv') $null    # download_nightlife.ps1
$danran  = Count-Gu (Join-Path $Root '외국인_공공데이터\업소_단란주점_인허가.csv') $null

$info = @{}
$facility = foreach ($r in (Import-Csv (Join-Path $Root '태블로_외국인분석\자치구_정보.csv') -Encoding UTF8)) {
    $g = $r.'자치구'
    $o = [pscustomobject][ordered]@{
        '자치구' = $g; '자치구코드' = $r.'자치구코드'
        '숙박_합계' = $r.'숙박_합계'; '호텔_수' = $r.'호텔_수'; '호텔_객실수' = $r.'호텔_객실수'
        '외국인민박_수' = $r.'외국인민박_수'; '외국인민박_객실수' = $r.'외국인민박_객실수'
        '일반숙박_수' = [int]$motel[$g]
        '관광장소_합계' = $r.'관광장소_합계'; '명소_수' = $r.'명소_수'; '쇼핑_수' = $r.'쇼핑_수'; '음식점_수' = $r.'음식점_수'
        '관광특구_수' = $r.'관광특구_수'
        '유흥_합계' = [int]$yuheung[$g] + [int]$danran[$g]; '유흥주점_수' = [int]$yuheung[$g]; '단란주점_수' = [int]$danran[$g]
        '위도' = $guPos[$g][0]; '경도' = $guPos[$g][1]
    }
    $info[$r.'자치구'] = $o
    $o
}
$facility | Sort-Object '자치구' | Export-Csv (Join-Path $Out '자치구_시설.csv') -NoTypeInformation -Encoding UTF8

$guRows = foreach ($r in (Import-Csv (Join-Path $Root '국적별_분석\국적별_자치구별.csv') -Encoding UTF8)) {
    if ($r.'국적' -notin (@('전체') + $nats)) { continue }
    $o = [ordered]@{ '국적' = $r.'국적' }
    foreach ($k in '자치구', '하루평균인원', '평일_하루평균', '주말_하루평균', '주말증감률', '국적내비중', '특화지수') { $o[$k] = $r.$k }
    foreach ($p in $info[$r.'자치구'].PSObject.Properties) { if ($p.Name -ne '자치구') { $o[$p.Name] = $p.Value } }
    [pscustomobject]$o
}
$guRows | Export-Csv (Join-Path $Out '자치구_국적별.csv') -NoTypeInformation -Encoding UTF8

# ================= 2) 연휴 =================
# (a) 공식 공휴일: Nager.Date 공개 API (태국은 API에 없음)
$api = [ordered]@{ 'US' = '미국'; 'JP' = '일본'; 'CN' = '중국'; 'FR' = '프랑스'; 'CA' = '캐나다'; 'ID' = '인도네시아' }
$hol = New-Object System.Collections.Generic.List[object]
foreach ($cc in $api.Keys) {
    foreach ($h in (Invoke-RestMethod "https://date.nager.at/api/v3/PublicHolidays/2026/$cc" -TimeoutSec 60)) {
        if ($h.global -eq $false) { continue }   # 일부 주·지역만 쉬는 날은 뺌
        $hol.Add([pscustomobject][ordered]@{
            '국적' = $api[$cc]; '연휴명' = $h.localName; '영문명' = $h.name; '종류' = '공휴일'
            '시작일' = $h.date; '종료일' = $h.date; '출처' = 'Nager.Date API'
        })
    }
}
# (b) 주요 명절 연휴·방학 기간: 각국 정부·교육청 발표를 보고 직접 입력 (방학은 지역·학교마다 달라 대략적인 기간)
$manual = @(
    @('중국','원단 연휴','New Year','명절 연휴','2026-01-01','2026-01-03'),
    @('중국','춘절 연휴','Spring Festival','명절 연휴','2026-02-15','2026-02-23'),
    @('중국','청명절 연휴','Qingming','명절 연휴','2026-04-04','2026-04-06'),
    @('중국','노동절 연휴','Labour Day','명절 연휴','2026-05-01','2026-05-05'),
    @('중국','단오절 연휴','Dragon Boat','명절 연휴','2026-06-19','2026-06-21'),
    @('중국','중추절 연휴','Mid-Autumn','명절 연휴','2026-09-25','2026-09-27'),
    @('중국','국경절 연휴','National Day','명절 연휴','2026-10-01','2026-10-07'),
    @('중국','여름방학','Summer vacation','방학(대략)','2026-07-11','2026-08-31'),
    @('일본','연말연시','New Year holidays','명절 연휴','2026-01-01','2026-01-04'),
    @('일본','골든위크','Golden Week','명절 연휴','2026-04-29','2026-05-06'),
    @('일본','오봉','Obon','명절 연휴','2026-08-13','2026-08-16'),
    @('일본','실버위크','Silver Week','명절 연휴','2026-09-19','2026-09-23'),
    @('일본','여름방학','Summer vacation','방학(대략)','2026-07-20','2026-08-31'),
    @('태국','신정','New Year','공휴일','2026-01-01','2026-01-01'),
    @('태국','송끄란','Songkran','명절 연휴','2026-04-13','2026-04-15'),
    @('태국','여름방학','School summer break','방학(대략)','2026-03-15','2026-05-15'),
    @('태국','10월 방학','School October break','방학(대략)','2026-10-01','2026-10-31'),
    @('인도네시아','르바란 연휴(이둘 피트리)','Eid al-Fitr + cuti bersama','명절 연휴','2026-03-18','2026-03-24'),
    @('인도네시아','이둘 아드하','Eid al-Adha','공휴일','2026-05-27','2026-05-27'),
    @('인도네시아','학교 방학','School holidays','방학(대략)','2026-06-27','2026-07-12'),
    @('미국','봄방학','Spring break','방학(대략)','2026-03-07','2026-03-29'),
    @('미국','여름방학','Summer vacation','방학(대략)','2026-06-06','2026-08-23'),
    @('미국','추수감사절 연휴','Thanksgiving','명절 연휴','2026-11-26','2026-11-29'),
    @('프랑스','부활절 방학','Spring holidays','방학(대략)','2026-04-04','2026-05-03'),
    @('프랑스','여름방학','Summer vacation','방학(대략)','2026-07-04','2026-08-31'),
    @('프랑스','투생 방학','Toussaint holidays','방학(대략)','2026-10-17','2026-11-01'),
    @('캐나다','여름방학','Summer vacation','방학(대략)','2026-06-27','2026-09-07')
)
foreach ($m in $manual) {
    $hol.Add([pscustomobject][ordered]@{
        '국적' = $m[0]; '연휴명' = $m[1]; '영문명' = $m[2]; '종류' = $m[3]
        '시작일' = $m[4]; '종료일' = $m[5]; '출처' = '직접 입력 (각국 정부·교육청 발표 기준, 방학은 대략)'
    })
}
$holOut = foreach ($h in ($hol | Sort-Object '국적', '시작일')) {
    $s = [datetime]::ParseExact($h.'시작일', 'yyyy-MM-dd', $Inv); $e = [datetime]::ParseExact($h.'종료일', 'yyyy-MM-dd', $Inv)
    $o = [ordered]@{}; foreach ($p in $h.PSObject.Properties) { $o[$p.Name] = $p.Value }
    $o['일수'] = ($e - $s).Days + 1
    [pscustomobject]$o
}
$holOut | Export-Csv (Join-Path $Out '연휴_목록.csv') -NoTypeInformation -Encoding UTF8

# (c) 날짜 x 국적 + 그날의 연휴
$daily = @(Import-Csv (Join-Path $Root '국적별_분석\국적별_일별.csv') -Encoding UTF8 | Where-Object { $_.'국적' -in $nats })
$val = @{}; foreach ($r in $daily) { $val["$($r.'국적')|$($r.'날짜')"] = [double]$r.'하루평균인원' }
$monAvg = @{}
foreach ($g in ($daily | Group-Object '국적', '월')) { $monAvg["$($g.Group[0].'국적')|$($g.Group[0].'월')"] = ($g.Group | Measure-Object { [double]$_.'하루평균인원' } -Average).Average }
function Holidays($nat, $date) {
    @($holOut | Where-Object { $_.'국적' -eq $nat -and $_.'시작일' -le $date -and $_.'종료일' -ge $date } | ForEach-Object { $_.'연휴명' }) -join ' / '
}
$dayRows = foreach ($r in $daily) {
    $h = Holidays $r.'국적' $r.'날짜'
    $m = $monAvg["$($r.'국적')|$($r.'월')"]
    [pscustomobject][ordered]@{
        '날짜' = $r.'날짜'; '월' = $r.'월'; '요일' = $r.'요일'; '주말여부' = $r.'주말여부'; '국적' = $r.'국적'
        '하루평균인원' = $r.'하루평균인원'
        '월평균대비_변화율' = $(if ($m) { [Math]::Round(([double]$r.'하루평균인원' / $m - 1) * 100, 1) } else { '' })
        '연휴여부' = $(if ($h) { 'Y' } else { 'N' }); '연휴명' = $h
    }
}
$dayRows | Export-Csv (Join-Path $Out '일별_국적_연휴.csv') -NoTypeInformation -Encoding UTF8

# (d) 연휴 효과: 연휴 기간 하루 평균 vs 시작 전 28일(그 나라 다른 연휴 날 제외) 하루 평균
$allDates = @($daily | ForEach-Object { $_.'날짜' } | Sort-Object -Unique)   # Measure-Object 는 날짜를 못 다뤄서 글자로 정렬
$firstDay = [datetime]::ParseExact($allDates[0], 'yyyy-MM-dd', $Inv)
$lastDay  = [datetime]::ParseExact($allDates[-1], 'yyyy-MM-dd', $Inv)
$holDay = @{}   # 비교 기간에서 뺄 날 = 공휴일·명절 연휴 (방학은 몇 달씩 길어서 빼지 않음)
foreach ($h in ($holOut | Where-Object { $_.'종류' -ne '방학(대략)' })) {
    $s = [datetime]::ParseExact($h.'시작일', 'yyyy-MM-dd', $Inv); $e = [datetime]::ParseExact($h.'종료일', 'yyyy-MM-dd', $Inv)
    for ($d = $s; $d -le $e; $d = $d.AddDays(1)) { $holDay["$($h.'국적')|$($d.ToString('yyyy-MM-dd'))"] = 1 }
}
$effect = foreach ($h in $holOut) {
    $s = [datetime]::ParseExact($h.'시작일', 'yyyy-MM-dd', $Inv); $e = [datetime]::ParseExact($h.'종료일', 'yyyy-MM-dd', $Inv)
    if ($s -gt $lastDay -or $s.AddDays(-28) -lt $firstDay) { continue }   # 데이터 기간 밖이거나 비교할 앞 기간이 없음
    $in = @(); for ($d = $s; $d -le $e -and $d -le $lastDay; $d = $d.AddDays(1)) { $k = "$($h.'국적')|$($d.ToString('yyyy-MM-dd'))"; if ($val.ContainsKey($k)) { $in += $val[$k] } }
    $before = @(); for ($d = $s.AddDays(-28); $d -lt $s; $d = $d.AddDays(1)) { $k = "$($h.'국적')|$($d.ToString('yyyy-MM-dd'))"; if ($val.ContainsKey($k) -and -not $holDay.ContainsKey($k)) { $before += $val[$k] } }
    if (-not $in.Count -or $before.Count -lt 7) { continue }
    $a = ($in | Measure-Object -Average).Average; $b = ($before | Measure-Object -Average).Average
    [pscustomobject][ordered]@{
        '국적' = $h.'국적'; '연휴명' = $h.'연휴명'; '종류' = $h.'종류'; '시작일' = $h.'시작일'; '종료일' = $h.'종료일'
        '연휴기간_하루평균' = [Math]::Round($a, 1); '직전4주_하루평균' = [Math]::Round($b, 1)
        '변화율' = [Math]::Round(($a / $b - 1) * 100, 1)
        '비고' = $(if ($e -gt $lastDay) { "데이터가 $($lastDay.ToString('yyyy-MM-dd'))까지라 연휴 일부만 반영" } else { '' })
    }
}
$effect | Sort-Object '국적', '시작일' | Export-Csv (Join-Path $Out '연휴_효과.csv') -NoTypeInformation -Encoding UTF8

# (e) 연휴 x 자치구: 위 (d)와 같은 비교를 구마다 따로 (원본: 자치구 x 시간 x 국적)
$guDay = @{}   # "국적|자치구|날짜" -> 하루 합계(시간 24개 합)
$hdr = $null
foreach ($line in [IO.File]::ReadLines((Join-Path $Root '외국인_관광\합본\외국인생활인구_단기_전체.csv'), [Text.Encoding]::UTF8)) {
    $f = $line.Replace('"', '').Split(',')
    if (-not $hdr) {
        $hdr = $f; $iD = [array]::IndexOf($hdr, '날짜'); $iG = [array]::IndexOf($hdr, '자치구')
        $natIdx = @{}; foreach ($n in $nats) { $natIdx[$n] = [array]::IndexOf($hdr, $n) }
        continue
    }
    foreach ($n in $nats) {
        $v = $f[$natIdx[$n]]; if (-not $v) { continue }   # 빈칸(인원이 적어 비공개) = 0
        $k = "$n|$($f[$iG])|$($f[$iD])"; $guDay[$k] = [double]$guDay[$k] + [double]::Parse($v, $Inv)
    }
}
$guNames = @($info.Keys | Sort-Object)
$holGu = foreach ($h in $effect) {
    $s = [datetime]::ParseExact($h.'시작일', 'yyyy-MM-dd', $Inv); $e = [datetime]::ParseExact($h.'종료일', 'yyyy-MM-dd', $Inv)
    $inDays = @(); for ($d = $s; $d -le $e -and $d -le $lastDay; $d = $d.AddDays(1)) { $inDays += $d.ToString('yyyy-MM-dd') }
    $beDays = @(); for ($d = $s.AddDays(-28); $d -lt $s; $d = $d.AddDays(1)) { $ds = $d.ToString('yyyy-MM-dd'); if (-not $holDay.ContainsKey("$($h.'국적')|$ds")) { $beDays += $ds } }
    $calc = foreach ($g in $guNames) {
        $a = 0.0; foreach ($ds in $inDays) { $a += [double]$guDay["$($h.'국적')|$g|$ds"] }; $a = $a / 24 / $inDays.Count
        $b = 0.0; foreach ($ds in $beDays) { $b += [double]$guDay["$($h.'국적')|$g|$ds"] }; $b = $b / 24 / $beDays.Count
        [pscustomobject]@{ G = $g; A = $a; B = $b }
    }
    $upTot = 0.0; foreach ($c in $calc) { if ($c.A -gt $c.B) { $upTot += $c.A - $c.B } }
    foreach ($c in $calc) {
        $o = [ordered]@{
            '국적' = $h.'국적'; '연휴명' = $h.'연휴명'; '종류' = $h.'종류'; '시작일' = $h.'시작일'; '종료일' = $h.'종료일'; '자치구' = $c.G
            '연휴기간_하루평균' = [Math]::Round($c.A, 1); '직전4주_하루평균' = [Math]::Round($c.B, 1)
            '증가인원' = [Math]::Round($c.A - $c.B, 1)
            '변화율' = $(if ($c.B -ge 5) { [Math]::Round(($c.A / $c.B - 1) * 100, 1) } else { '' })   # 평소 5명 미만인 구는 % 가 크게 튀어서 비움
            '늘어난사람중_비중' = $(if ($upTot -and $c.A -gt $c.B) { [Math]::Round(($c.A - $c.B) / $upTot * 100, 1) } else { 0 })
        }
        foreach ($k in '숙박_합계', '호텔_수', '외국인민박_수', '일반숙박_수', '관광장소_합계', '명소_수', '쇼핑_수', '음식점_수', '유흥_합계', '위도', '경도') { $o[$k] = $info[$c.G].$k }
        [pscustomobject]$o
    }
}
$holGu | Export-Csv (Join-Path $Out '연휴_자치구.csv') -NoTypeInformation -Encoding UTF8

# ================= 3) 월별 방문자 x 환율 x 기온 ("검증했지만 영향이 작았다" 차트용) =================
# 먼저 최신화: make_exchange_csv.ps1, make_weather_csv.ps1
$fxBy = @{}; foreach ($r in (Import-Csv (Join-Path $Root '환율\환율_월별.csv') -Encoding UTF8)) { $fxBy["$($r.'월')|$($r.'국적')"] = $r }
$wxBy = @{}; foreach ($r in (Import-Csv (Join-Path $Root '날씨\csv\날씨_월별_국가별.csv') -Encoding UTF8)) { $wxBy["$($r.'월')|$($r.'국적')"] = $r }
$visitM = @(Import-Csv (Join-Path $Root '국적별_분석\국적별_월별.csv') -Encoding UTF8 | Where-Object { $_.'국적' -in $nats })
$janV = @{}; foreach ($r in $visitM) { if ($r.'월' -eq '2026-01') { $janV[$r.'국적'] = [double]$r.'하루평균인원' } }
$monthRows = foreach ($r in ($visitM | Sort-Object '국적', '월')) {
    $k = "$($r.'월')|$($r.'국적')"; $fx = $fxBy[$k]; $wx = $wxBy[$k]
    [pscustomobject][ordered]@{
        '월' = $r.'월'; '국적' = $r.'국적'
        '하루평균인원' = $r.'하루평균인원'
        '인원_1월대비_변화율' = [Math]::Round(([double]$r.'하루평균인원' / $janV[$r.'국적'] - 1) * 100, 1)
        '통화' = $fx.'통화'; '월평균_원화환율' = $fx.'월평균_원화환율'; '단위' = $fx.'단위'
        '환율_1월대비_변화율' = $fx.'1월대비_변화율'
        '도시' = $wx.'도시'; '현지_월평균기온' = $wx.'월평균기온'; '서울_월평균기온' = $wx.'서울_월평균기온'; '서울보다_따뜻함' = $wx.'서울보다_따뜻함'
        '집계일수' = $r.'집계일수'
    }
}
$monthRows | Export-Csv (Join-Path $Out '월별_방문_환율_기온.csv') -NoTypeInformation -Encoding UTF8

# ================= 4) 통합 표: 하루 x 국적 x 자치구 = 한 줄 (Tableau에서 시트 하나로 모든 차트) =================
# 연휴명: 직접 입력한 명절·방학 (하루짜리 API 공휴일은 뺌). 방학 안에 명절이 들어 있으면(태국 여름방학 ⊃ 송끄란 등) 그 방학은 뺌
$major = @($holOut | Where-Object { $_.'출처' -like '직접*' })
$major = @($major | Where-Object {
    $h = $_
    -not ($h.'종류' -eq '방학(대략)' -and @($major | Where-Object { $_.'국적' -eq $h.'국적' -and $_.'종류' -eq '명절 연휴' -and $_.'시작일' -ge $h.'시작일' -and $_.'종료일' -le $h.'종료일' }).Count)
})
$ko = [Globalization.CultureInfo]::GetCultureInfo('ko-KR')
$fxDay = @{}; foreach ($r in (Import-Csv (Join-Path $Root '환율\환율_일별_국가별.csv') -Encoding UTF8)) { $fxDay["$($r.'국적')|$($r.'날짜')"] = $r }
$wxDay = @{}; foreach ($r in (Import-Csv (Join-Path $Root '날씨\csv\날씨_일별_국가별.csv') -Encoding UTF8)) { $wxDay["$($r.'국적')|$($r.'날짜')"] = $r }
$base = @{}   # "연휴|국적|자치구" -> 직전 4주 하루 평균 (다른 공휴일·명절 날 제외, 7일 미만이면 없음)
function Baseline($h, $g) {
    $k = "$($h.'연휴명')|$($h.'국적')|$g"
    if ($base.ContainsKey($k)) { return $base[$k] }
    $s = [datetime]::ParseExact($h.'시작일', 'yyyy-MM-dd', $Inv)
    $v = @(); for ($d = $s.AddDays(-28); $d -lt $s; $d = $d.AddDays(1)) {
        $ds = $d.ToString('yyyy-MM-dd')
        if ($d -ge $firstDay -and -not $holDay.ContainsKey("$($h.'국적')|$ds")) { $v += [double]$guDay["$($h.'국적')|$g|$ds"] / 24 }
    }
    $base[$k] = if ($v.Count -ge 7) { ($v | Measure-Object -Average).Average } else { $null }
    $base[$k]
}
$allRows = foreach ($ds in $allDates) {
    $dt = [datetime]::ParseExact($ds, 'yyyy-MM-dd', $Inv)
    foreach ($n in $nats) {
        $h = @($major | Where-Object { $_.'국적' -eq $n -and $_.'시작일' -le $ds -and $_.'종료일' -ge $ds } | Sort-Object '일수' | Select-Object -First 1)
        $fx = $fxDay["$n|$ds"]; $wx = $wxDay["$n|$ds"]
        foreach ($g in $guNames) {
            $v = [double]$guDay["$n|$g|$ds"] / 24
            $b = if ($h.Count) { Baseline $h[0] $g } else { $null }
            $f = $info[$g]
            [pscustomobject][ordered]@{
                '날짜' = $ds; '월' = $ds.Substring(0, 7); '요일' = $dt.ToString('ddd', $ko)
                '주말여부' = $(if ($dt.DayOfWeek -in 'Saturday', 'Sunday') { 'Y' } else { 'N' })
                '국적' = $n; '자치구' = $g
                '인원' = [Math]::Round($v, 1)
                '연휴명' = $(if ($h.Count) { $h[0].'연휴명' } else { '' })
                '연휴종류' = $(if ($h.Count) { $h[0].'종류' } else { '' })
                '평소인원' = $(if ($null -ne $b) { [Math]::Round($b, 1) } else { '' })
                '증가인원' = $(if ($null -ne $b) { [Math]::Round($v - $b, 1) } else { '' })
                '원화환율' = $fx.'원화환율'; '단위' = $fx.'단위'
                '현지기온' = $wx.'평균기온'; '서울기온' = $wx.'서울_평균기온'; '서울보다_따뜻함' = $wx.'서울보다_따뜻함'
                '호텔_수' = $f.'호텔_수'; '외국인민박_수' = $f.'외국인민박_수'; '명소_수' = $f.'명소_수'; '쇼핑_수' = $f.'쇼핑_수'; '음식점_수' = $f.'음식점_수'
                '위도' = $f.'위도'; '경도' = $f.'경도'
            }
        }
    }
}
$allDir = Join-Path $Root '해커톤_데이터\통합_csv'
New-Item -ItemType Directory -Force -Path $allDir | Out-Null
$allRows | Export-Csv (Join-Path $allDir '통합.csv') -NoTypeInformation -Encoding UTF8

$readme = @(
    "해커톤 데이터 (만든 시각: $((Get-Date).ToString('yyyy-MM-dd HH:mm')))",
    '해커톤_데이터.xlsx 파일 하나에 아래 표가 시트별로 들어 있습니다. Tableau에서 "Microsoft Excel"로 이 파일을 열면 왼쪽에 시트가 모두 보입니다.',
    '같은 내용의 CSV 원본은 csv 폴더(자치구·연휴)와 프로젝트\동별_분석 폴더(행정동)에 있습니다.',
    '',
    '[자치구]',
    '자치구_국적별 : 한 줄 = 자치구 x 국적(전체·중국·미국·일본·태국·인도네시아·프랑스·캐나다). 이 파일 하나로 "어디에 왜 많나" 대시보드를 만들 수 있습니다.',
    '  하루평균인원·평일·주말 = 2026-01-01 ~ 10-18 하루 평균 단기체류 외국인 (같은 사람이 여러 날 머물면 매일 잡힘)',
    '  특화지수 = 1보다 크면 그 나라 사람이 다른 외국인보다 이 구에 더 몰림',
    '  숙박_합계 = 호텔_수 + 외국인민박_수 (영업 중). 일반숙박_수 = 모텔·여관 등 (영업 중). 관광장소_합계 = 명소_수 + 쇼핑_수 + 음식점_수 (서울 관광 누리집 visitseoul 목록 기준)',
    '  유흥_합계 = 유흥주점_수 + 단란주점_수 (영업 중, 서울시 인허가). 유흥주점의 약 3/4가 룸살롱이라 홍대·이태원 같은 관광 밤 문화는 잘 안 잡힘(클럽·감성주점은 대부분 일반음식점으로 등록)',
    '  쇼핑_수 = 쇼핑몰·백화점·시장·면세점·편집숍 등 쇼핑 장소. 위도·경도 = 구청 위치',
    '  국적 필터를 꼭 걸어서 쓰세요 (안 걸면 같은 구의 시설 수가 국적 수만큼 더해짐).',
    '자치구_시설 : 한 줄 = 자치구 하나. 시설 수만.',
    '',
    '[행정동] (make_dong_csv.ps1 이 만든 동별_분석 폴더의 CSV를 엑셀로 바꿔 둔 것, 2026-05-01 ~ 10-18)',
    '동별_국적별_외국인 : 한 줄 = 행정동 x 국적. 하루평균인원, 특화지수, 동내_국적비율(예: 대림2동 중국 87%) + 그 동의 호텔·민박·일반숙박·명소 수, 동 중심 위도·경도.',
    '  쇼핑·음식점은 위치 좌표가 없어 동 단위에는 없습니다. 국적 필터를 꼭 걸어서 쓰세요.',
    '동별_시설 : 한 줄 = 행정동 하나. 숙박·명소 수만.',
    '',
    '[연휴]',
    '연휴_목록 : 나라별 2026년 공휴일(Nager.Date API) + 명절 연휴·방학(직접 입력). 태국은 API에 없어 직접 입력만 있습니다.',
    '  방학은 지역·학교마다 달라서 대략적인 기간입니다. 발표 전에 중요한 날짜는 한 번 더 확인하세요.',
    '연휴_효과 : 연휴 하나 = 한 줄. 연휴 기간 하루 평균 외국인 vs 연휴 시작 전 4주(다른 공휴일·명절 날 제외) 하루 평균, 변화율(%).',
    '일별_국적_연휴 : 날짜 x 국적 = 한 줄. 하루평균인원, 그 달 평균 대비 변화율, 그날 그 나라 연휴 이름. 선 그래프 + 색상=연휴여부 로 쓰기 좋음.',
    '연휴_자치구 : 연휴 x 자치구 = 한 줄. 연휴_효과를 구마다 따로 계산 + 그 구의 숙박·관광지·쇼핑 수, 구청 위도·경도.',
    '  증가인원 = 연휴기간 하루평균 - 직전4주 하루평균. 변화율은 평소 5명 미만인 구는 비움(작은 수라 %가 크게 튐).',
    '  늘어난사람중_비중 = 그 나라 사람이 늘어난 구들의 증가분 합계 중 이 구가 차지한 %. "늘어난 태국인의 몇 %가 이 구로 갔나".',
    '  국적과 연휴명 필터를 꼭 걸어서 쓰세요.',
    '',
    '[월별 방문자 x 환율 x 기온]',
    '월별_방문_환율_기온 : 한 줄 = 한 달 x 국적. "환율·날씨도 확인했지만 영향이 작았다"를 보여주는 차트용.',
    '  인원_1월대비_변화율 = 1월보다 하루 평균 인원이 몇 % 변했나',
    '  환율_1월대비_변화율 = 그 나라 돈 1단위(엔·루피아 100단위)의 원화 값이 1월보다 몇 % 변했나. 마이너스 = 원화가 비싸짐 = 그 나라 사람에게 한국 여행이 비싸짐',
    '  월평균_원화환율 = 그 나라 돈 1단위(엔은 100엔)가 몇 원인지 (단위 칸 참고). 오르면 = 그 나라 사람에게 한국 여행이 싸짐',
    '  서울보다_따뜻함 = 그 나라 수도의 월평균기온 - 서울 월평균기온 (도시 칸 참고)',
    '  10월은 외국인 데이터가 18일까지만 있습니다(집계일수 참고). 국적 필터를 걸어서 쓰세요.',
    '다시 만들기: make_hackathon_data.ps1, make_dong_csv.ps1 실행 -> make_hackathon_xlsx.ps1 실행'
)
[IO.File]::WriteAllLines((Join-Path $Root '해커톤_데이터\읽어주세요.txt'), $readme, (New-Object Text.UTF8Encoding($true)))
"OK 자치구 $(@($guRows).Count)줄, 연휴 $(@($holOut).Count)개, 연휴효과 $(@($effect).Count)개, 일별 $(@($dayRows).Count)줄 -> $Out"
